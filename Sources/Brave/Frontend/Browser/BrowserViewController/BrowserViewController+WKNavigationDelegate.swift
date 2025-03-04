/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Shared
import Data
import BraveShields
import Preferences
import BraveCore
import BraveUI
import BraveWallet
import os.log
import Favicon
import Growth
import SafariServices
import LocalAuthentication
import BraveShared
import UniformTypeIdentifiers

extension WKNavigationAction {
  /// Allow local requests only if the request is privileged.
  /// If the request is internal or unprivileged, we should deny it.
  var isInternalUnprivileged: Bool {
    guard let url = request.url else {
      return true
    }

    if let url = InternalURL(url) {
      return !url.isAuthorized
    } else {
      return false
    }
  }
}

extension WKNavigationType: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .linkActivated: return "linkActivated"
    case .formResubmitted: return "formResubmitted"
    case .backForward: return "backForward"
    case .formSubmitted: return "formSubmitted"
    case .other: return "other"
    case .reload: return "reload"
    @unknown default:
      return "Unknown(\(rawValue))"
    }
  }
}

extension UTType {
  static let textCalendar = UTType(mimeType: "text/calendar")! // Not the same as `calendarEvent`
  static let mobileConfiguration = UTType(mimeType: "application/x-apple-aspen-config")!
}

// MARK: WKNavigationDelegate
extension BrowserViewController: WKNavigationDelegate {
  public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    if tabManager.selectedTab?.webView !== webView {
      return
    }
    toolbarVisibilityViewModel.toolbarState = .expanded

    if let selectedTab = tabManager.selectedTab,
       selectedTab.url?.origin != webView.url?.origin {
      // new site has a different origin, hide wallet icon.
      tabManager.selectedTab?.isWalletIconVisible = false
      // new site, reset connected addresses
      tabManager.selectedTab?.clearSolanaConnectedAccounts()
      // close wallet panel if it's open
      if let popoverController = self.presentedViewController as? PopoverController,
         popoverController.contentController is WalletPanelHostingController {
        self.dismiss(animated: true)
      }
    }

    if #unavailable(iOS 16.0) {
      updateFindInPageVisibility(visible: false)
    }
    displayPageZoom(visible: false)

    // If we are going to navigate to a new page, hide the reader mode button. Unless we
    // are going to a about:reader page. Then we keep it on screen: it will change status
    // (orange color) as soon as the page has loaded.
    if let url = webView.url {
      if !url.isReaderModeURL {
        topToolbar.updateReaderModeState(ReaderModeState.unavailable)
        hideReaderModeBar(animated: false)
      }
    }
  }

  // Recognize an Apple Maps URL. This will trigger the native app. But only if a search query is present.
  // Otherwise it could just be a visit to a regular page on maps.apple.com.
  // Exchaging https/https scheme with maps in order to open URLS properly on Apple Maps
  fileprivate func isAppleMapsURL(_ url: URL) -> (enabled: Bool, url: URL)? {
    if url.scheme == "http" || url.scheme == "https" {
      if url.host == "maps.apple.com" && url.query != nil {
        guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
          return nil
        }
        urlComponents.scheme = "maps"

        if let url = urlComponents.url {
          return (true, url)
        }
        return nil
      }
    }
    return (false, url)
  }

  // Recognize a iTunes Store URL. These all trigger the native apps. Note that appstore.com and phobos.apple.com
  // used to be in this list. I have removed them because they now redirect to itunes.apple.com. If we special case
  // them then iOS will actually first open Safari, which then redirects to the app store. This works but it will
  // leave a 'Back to Safari' button in the status bar, which we do not want.
  fileprivate func isStoreURL(_ url: URL) -> Bool {
    let isStoreScheme = ["itms-apps", "itms-appss", "itmss"].contains(url.scheme)
    if isStoreScheme {
      return true
    }

    let isHttpScheme = ["http", "https"].contains(url.scheme)
    let isAppStoreHost = ["itunes.apple.com", "apps.apple.com", "appsto.re"].contains(url.host)
    return isHttpScheme && isAppStoreHost
  }

  // This is the place where we decide what to do with a new navigation action. There are a number of special schemes
  // and http(s) urls that need to be handled in a different way. All the logic for that is inside this delegate
  // method.

  fileprivate func isUpholdOAuthAuthorization(_ url: URL) -> Bool {
    return url.scheme == "rewards" && url.host == "uphold"
  }

  @MainActor
  public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
    guard var requestURL = navigationAction.request.url else {
      return (.cancel, preferences)
    }
    if InternalURL.isValid(url: requestURL) {
      if navigationAction.navigationType != .backForward, navigationAction.isInternalUnprivileged,
          (navigationAction.sourceFrame != nil || navigationAction.targetFrame?.isMainFrame == false || navigationAction.request.cachePolicy == .useProtocolCachePolicy) {
        Logger.module.warning("Denying unprivileged request: \(navigationAction.request)")
        return (.cancel, preferences)
      }

      return (.allow, preferences)
    }

    if requestURL.scheme == "about" {
      return (.allow, preferences)
    }

    if requestURL.isBookmarklet {
      return (.cancel, preferences)
    }

    // Universal links do not work if the request originates from the app, manual handling is required.
    if let mainDocURL = navigationAction.request.mainDocumentURL,
      let universalLink = UniversalLinkManager.universalLinkType(for: mainDocURL, checkPath: true) {
      switch universalLink {
      case .buyVPN:
        presentCorrespondingVPNViewController()
        return (.cancel, preferences)
      }
    }

    // First special case are some schemes that are about Calling. We prompt the user to confirm this action. This
    // gives us the exact same behaviour as Safari.
    let tab = tab(for: webView)
    
    if ["sms", "tel", "facetime", "facetime-audio"].contains(requestURL.scheme) {
      // Do not allow opening external URLs from child tabs
      handleExternalURL(requestURL, tab: tab, navigationAction: navigationAction)
      return (.cancel, preferences)
    }

    // Second special case are a set of URLs that look like regular http links, but should be handed over to iOS
    // instead of being loaded in the webview.
    // In addition we are exchaging actual scheme with "maps" scheme
    // So the Apple maps URLs will open properly
    if let mapsURL = isAppleMapsURL(requestURL), mapsURL.enabled {
      // Do not allow opening external URLs from child tabs
      handleExternalURL(mapsURL.url, tab: tab, navigationAction: navigationAction)
      return (.cancel, preferences)
    }

    if isStoreURL(requestURL) {
      // Do not allow opening external URLs from child tabs
      handleExternalURL(requestURL, tab: tab, navigationAction: navigationAction)
      return (.cancel, preferences)
    }

    // Handles custom mailto URL schemes.
    if requestURL.scheme == "mailto" {
      // Do not allow opening external URLs from child tabs
      handleExternalURL(requestURL, tab: tab, navigationAction: navigationAction)
      return (.cancel, preferences)
    }
    
    // handles IPFS URL schemes
    if requestURL.isIPFSScheme {
      if navigationAction.targetFrame?.isMainFrame == true {
        handleIPFSSchemeURL(requestURL)
      }
      return (.cancel, preferences)
    }
    
    // handles Decentralized DNS
    if let decentralizedDNSHelper = self.decentralizedDNSHelperFor(url: requestURL),
       navigationAction.targetFrame?.isMainFrame == true {
      topToolbar.locationView.loading = true
      let result = await decentralizedDNSHelper.lookup(domain: requestURL.schemelessAbsoluteDisplayString)
      topToolbar.locationView.loading = tabManager.selectedTab?.loading ?? false
      guard !Task.isCancelled else { // user pressed stop, or typed new url
        return (.cancel, preferences)
      }
      switch result {
      case let .loadInterstitial(service):
        showWeb3ServiceInterstitialPage(service: service, originalURL: requestURL)
        return (.cancel, preferences)
      case let .load(resolvedURL):
        if resolvedURL.isIPFSScheme {
          handleIPFSSchemeURL(resolvedURL)
          return (.cancel, preferences)
        } else { // non-ipfs, treat as normal url / link tapped
          requestURL = resolvedURL
        }
      case .none:
        break
      }
    }

    let isPrivateBrowsing = privateBrowsingManager.isPrivateBrowsing
    tab?.currentRequestURL = requestURL
    
    // Website redirection logic
    if requestURL.isWebPage(includeDataURIs: false),
       navigationAction.targetFrame?.isMainFrame == true,
       let redirectURL = WebsiteRedirects.redirect(for: requestURL) {
      
      tab?.loadRequest(URLRequest(url: redirectURL))
      return (.cancel, preferences)
    }
    
    // before loading any ad-block scripts
    // await the preparation of the ad-block services
    await LaunchHelper.shared.prepareAdBlockServices(
      adBlockService: self.braveCore.adblockService
    )
    
    if let mainDocumentURL = navigationAction.request.mainDocumentURL {
      if mainDocumentURL != tab?.currentPageData?.mainFrameURL {
        // Clear the current page data if the page changes.
        // Do this before anything else so that we have a clean slate.
        tab?.currentPageData = PageData(mainFrameURL: mainDocumentURL)
      }
      
      let domainForMainFrame = Domain.getOrCreate(forUrl: mainDocumentURL, persistent: !isPrivateBrowsing)
      
      if let tab = tab, let modifiedRequest = getInternalRedirect(
        from: navigationAction, in: tab, domainForMainFrame: domainForMainFrame) {
        tab.isInternalRedirect = true
        tab.loadRequest(modifiedRequest)
        
        if let url = modifiedRequest.url {
          ContentBlockerManager.log.debug("Redirected user to `\(url.absoluteString, privacy: .private)`")
        }
        
        return (.cancel, preferences)
      } else {
        tab?.isInternalRedirect = false
      }
      
      // Set some additional user scripts
      if navigationAction.targetFrame?.isMainFrame == true {
        tab?.setScripts(scripts: [
          // Add de-amp script
          // The user script manager will take care to not reload scripts if this value doesn't change
          .deAmp: Preferences.Shields.autoRedirectAMPPages.value,
          
          // Add request blocking script
          // This script will block certian `xhr` and `window.fetch()` requests
          .requestBlocking: requestURL.isWebPage(includeDataURIs: false) &&
                            domainForMainFrame.isShieldExpected(.AdblockAndTp, considerAllShieldsOption: true),
          
          // The tracker protection script
          // This script will track what is blocked and increase stats
          .trackerProtectionStats: requestURL.isWebPage(includeDataURIs: false) &&
                                   domainForMainFrame.isShieldExpected(.AdblockAndTp, considerAllShieldsOption: true)
        ])
      }
      
      // Check if custom user scripts must be added to or removed from the web view.
      if let targetFrame = navigationAction.targetFrame {
        tab?.currentPageData?.addSubframeURL(forRequestURL: requestURL, isForMainFrame: targetFrame.isMainFrame)
        let scriptTypes = await tab?.currentPageData?.makeUserScriptTypes(domain: domainForMainFrame) ?? []
        tab?.setCustomUserScript(scripts: scriptTypes)
      }
    }

    // Brave Search logic.

    if navigationAction.targetFrame?.isMainFrame == true,
      BraveSearchManager.isValidURL(requestURL) {

      // Add Brave Search headers if Rewards is enabled
      if !isPrivateBrowsing && rewards.isEnabled && navigationAction.request.allHTTPHeaderFields?["X-Brave-Ads-Enabled"] == nil {
        var modifiedRequest = URLRequest(url: requestURL)
        modifiedRequest.setValue("1", forHTTPHeaderField: "X-Brave-Ads-Enabled")
        tab?.loadRequest(modifiedRequest)
        return (.cancel, preferences)
      }

      // We fetch cookies to determine if backup search was enabled on the website.
      let profile = self.profile
      let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
      tab?.braveSearchManager = BraveSearchManager(profile: profile, url: requestURL, cookies: cookies)
      if let braveSearchManager = tab?.braveSearchManager {
        braveSearchManager.fallbackQueryResultsPending = true
        braveSearchManager.shouldUseFallback { backupQuery in
          guard let query = backupQuery else {
            braveSearchManager.fallbackQueryResultsPending = false
            return
          }

          if query.found {
            braveSearchManager.fallbackQueryResultsPending = false
          } else {
            braveSearchManager.backupSearch(with: query) { completion in
              braveSearchManager.fallbackQueryResultsPending = false
              tab?.injectResults()
            }
          }
        }
      }
    } else {
      tab?.braveSearchManager = nil
    }

    // This is the normal case, opening a http or https url, which we handle by loading them in this WKWebView. We
    // always allow this. Additionally, data URIs are also handled just like normal web pages.

    if ["http", "https", "data", "blob", "file"].contains(requestURL.scheme) {
      if navigationAction.targetFrame?.isMainFrame == true {
        tab?.updateUserAgent(webView, newURL: requestURL)
      }

      pendingRequests[requestURL.absoluteString] = navigationAction.request

      // Adblock logic,
      // Only use main document URL, not the request URL
      // If an iFrame is loaded, shields depending on the main frame, not the iFrame request

      // Weird behavior here with `targetFram` and `sourceFrame`, on refreshing page `sourceFrame` is not nil (it is non-optional)
      //  however, it is still an uninitialized object, making it an unreliable source to compare `isMainFrame` against.
      //  Rather than using `sourceFrame.isMainFrame` or even comparing `sourceFrame == targetFrame`, a simple URL check is used.
      // No adblocking logic is be used on session restore urls. It uses javascript to retrieve the
      // request then the page is reloaded with a proper url and adblocking rules are applied.
      if let mainDocumentURL = navigationAction.request.mainDocumentURL,
        mainDocumentURL.schemelessAbsoluteString == requestURL.schemelessAbsoluteString,
        !(InternalURL(requestURL)?.isSessionRestore ?? false),
        navigationAction.sourceFrame.isMainFrame || navigationAction.targetFrame?.isMainFrame == true {
        // Identify specific block lists that need to be applied to the requesting domain
        let domainForShields = Domain.getOrCreate(forUrl: mainDocumentURL, persistent: !isPrivateBrowsing)
        
        // Load rule lists
        let ruleLists = await ContentBlockerManager.shared.ruleLists(for: domainForShields)
        tab?.contentBlocker.set(ruleLists: ruleLists)
      }
      
      let documentTargetURL: URL? = navigationAction.request.mainDocumentURL ??
                                    navigationAction.targetFrame?.request.mainDocumentURL ??
                                    requestURL   // Should be the same as the sourceFrame URL
      if let documentTargetURL = documentTargetURL {
        let domainForShields = Domain.getOrCreate(forUrl: documentTargetURL, persistent: !isPrivateBrowsing)
        let isScriptsEnabled = !domainForShields.isShieldExpected(.NoScript, considerAllShieldsOption: true)
        preferences.allowsContentJavaScript = isScriptsEnabled
      }

      // Cookie Blocking code below
      if let tab = tab {
        tab.setScript(script: .cookieBlocking, enabled: Preferences.Privacy.blockAllCookies.value)
      }

      // Reset the block alert bool on new host.
      if let newHost: String = requestURL.host, let oldHost: String = webView.url?.host, newHost != oldHost {
        self.tabManager.selectedTab?.alertShownCount = 0
        self.tabManager.selectedTab?.blockAllAlerts = false
      }

      return (.allow, preferences)
    }

    // Standard schemes are handled in previous if-case.
    // This check handles custom app schemes to open external apps.
    // Our own 'brave' scheme does not require the switch-app prompt.
    if requestURL.scheme?.contains("brave") == false {
      // Do not allow opening external URLs from child tabs
      handleExternalURL(requestURL, tab: tab, navigationAction: navigationAction) { didOpenURL in
        // Do not show error message for JS navigated links or redirect
        // as it's not the result of a user action.
        if !didOpenURL, navigationAction.navigationType == .linkActivated {
          let alert = UIAlertController(title: Strings.unableToOpenURLErrorTitle, message: Strings.unableToOpenURLError, preferredStyle: .alert)
          alert.addAction(UIAlertAction(title: Strings.OKString, style: .default, handler: nil))
          self.present(alert, animated: true, completion: nil)
        }
      }
    }
    
    return (.cancel, preferences)
  }
  
  /// Handles a link by opening it in an SFSafariViewController and presenting it on the BVC.
  ///
  /// This is unfortunately neccessary to handle certain downloads natively such as ics/calendar invites and
  /// mobileconfiguration files.
  ///
  /// The user unfortunately has to  dismiss it manually after they have handled the file.
  /// Chrome iOS does the same
  private func handleLinkWithSafariViewController(_ url: URL, tab: Tab?) {
    let vc = SFSafariViewController(url: url, configuration: .init())
    vc.modalPresentationStyle = .formSheet
    self.present(vc, animated: true)
    
    // If the website opened this URL in a separate tab, remove the empty tab
    if let tab = tab, tab.url == nil || tab.url?.absoluteString == "about:blank" {
      tabManager.removeTab(tab)
    }
  }

  @MainActor
  public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
    let isPrivateBrowsing = privateBrowsingManager.isPrivateBrowsing
    let response = navigationResponse.response
    let responseURL = response.url
    let tab = tab(for: webView)
    
    // Check if we upgraded to https and if so we need to update the url of frame evaluations
    if let responseURL = responseURL,
       let domain = tab?.currentPageData?.domain(persistent: !isPrivateBrowsing),
       tab?.currentPageData?.upgradeFrameURL(forResponseURL: responseURL, isForMainFrame: navigationResponse.isForMainFrame) == true {
      let scriptTypes = await tab?.currentPageData?.makeUserScriptTypes(domain: domain) ?? []
      tab?.setCustomUserScript(scripts: scriptTypes)
    }

    if let tab = tab,
      let responseURL = responseURL,
      InternalURL(responseURL)?.isSessionRestore == true {
      tab.shouldClassifyLoadsForAds = false
    }

    var request: URLRequest?
    if let url = responseURL {
      request = pendingRequests.removeValue(forKey: url.absoluteString)
    }

    // We can only show this content in the web view if this web view is not pending
    // download via the context menu.
    let canShowInWebView = navigationResponse.canShowMIMEType && (webView != pendingDownloadWebView)
    let forceDownload = webView == pendingDownloadWebView
    
    let mimeTypesThatRequireSFSafariViewControllerHandling: [UTType] = [
      .textCalendar,
      .mobileConfiguration
    ]
    
    // SFSafariViewController only supports http/https links
    if navigationResponse.isForMainFrame, let url = responseURL, url.isWebPage(includeDataURIs: false),
       let mimeType = response.mimeType.flatMap({ UTType(mimeType: $0) }),
       mimeTypesThatRequireSFSafariViewControllerHandling.contains(mimeType) {
      handleLinkWithSafariViewController(url, tab: tab)
      return .cancel
    }

    // Check if this response should be handed off to Passbook.
    if let passbookHelper = OpenPassBookHelper(request: request, response: response, canShowInWebView: canShowInWebView, forceDownload: forceDownload, browserViewController: self) {
      // Open our helper and cancel this response from the webview.
      passbookHelper.open()
      return .cancel
    }

    // Check if this response should be downloaded.
    let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
    if let downloadHelper = DownloadHelper(request: request, response: response, cookieStore: cookieStore, canShowInWebView: canShowInWebView, forceDownload: forceDownload) {
      // Clear the pending download web view so that subsequent navigations from the same
      // web view don't invoke another download.
      pendingDownloadWebView = nil

      let downloadAlertAction: (HTTPDownload) -> Void = { [weak self] download in
        self?.downloadQueue.enqueue(download)
      }

      // Open our helper and cancel this response from the webview.
      if let downloadAlert = downloadHelper.downloadAlert(from: view, okAction: downloadAlertAction) {
        present(downloadAlert, animated: true, completion: nil)
      }
      
      return .cancel
    }

    // If the content type is not HTML, create a temporary document so it can be downloaded and
    // shared to external applications later. Otherwise, clear the old temporary document.
    if let tab = tab, navigationResponse.isForMainFrame {
      if response.mimeType?.isKindOfHTML == false, let request = request {
        tab.temporaryDocument = TemporaryDocument(preflightResponse: response, request: request, tab: tab)
      } else {
        tab.temporaryDocument = nil
      }

      tab.mimeType = response.mimeType
    }
 
    // If none of our helpers are responsible for handling this response,
    // just let the webview handle it as normal.
    return .allow
  }

  nonisolated public func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {

    // If this is a certificate challenge, see if the certificate has previously been
    // accepted by the user.
    let host = challenge.protectionSpace.host
    let origin = "\(host):\(challenge.protectionSpace.port)"
    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
       let trust = challenge.protectionSpace.serverTrust,
       let cert = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first, profile.certStore.containsCertificate(cert, forOrigin: origin) {
      return (.useCredential, URLCredential(trust: trust))
    }
    
    // Certificate Pinning
    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
      if let serverTrust = challenge.protectionSpace.serverTrust {
        let host = challenge.protectionSpace.host
        let port = challenge.protectionSpace.port
        
        let result = BraveCertificateUtility.verifyTrust(serverTrust,
                                                         host: host,
                                                         port: port)
        let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] ?? []
        
        // Cert is valid and should be pinned
        if result == 0 {
          return (.useCredential, URLCredential(trust: serverTrust))
        }
        
        // Cert is valid and should not be pinned
        // Let the system handle it and we'll show an error if the system cannot validate it
        if result == Int32.min {
          return (.performDefaultHandling, nil)
        }
        
        // Cert is invalid and cannot be pinned
        Logger.module.error("CERTIFICATE_INVALID")
        let errorCode = CFNetworkErrors.braveCertificatePinningFailed.rawValue
        
        let underlyingError = NSError(domain: kCFErrorDomainCFNetwork as String,
                                      code: Int(errorCode),
                                      userInfo: ["_kCFStreamErrorCodeKey": Int(errorCode)])
        
        let error = await NSError(domain: kCFErrorDomainCFNetwork as String,
                                  code: Int(errorCode),
                                  userInfo: [NSURLErrorFailingURLErrorKey: webView.url as Any,
                                             "NSErrorPeerCertificateChainKey": certificateChain,
                                                     NSUnderlyingErrorKey: underlyingError])
        
        await MainActor.run {
          // Handle the error later in `didFailProvisionalNavigation`
          self.tab(for: webView)?.sslPinningError = error
        }
        
        return (.cancelAuthenticationChallenge, nil)
      }
    }
    
    // URLAuthenticationChallenge isn't Sendable atm
    let protectionSpace = challenge.protectionSpace
    let credential = challenge.proposedCredential
    let previousFailureCount = challenge.previousFailureCount
    return await Task { @MainActor in
      guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic ||
              protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest ||
              protectionSpace.authenticationMethod == NSURLAuthenticationMethodNTLM,
            let tab = tab(for: webView)
      else {
        return (.performDefaultHandling, nil)
      }
      
      // The challenge may come from a background tab, so ensure it's the one visible.
      tabManager.selectTab(tab)

      do {
        let credentials = try await Authenticator.handleAuthRequest(
          self,
          credential: credential,
          protectionSpace: protectionSpace,
          previousFailureCount: previousFailureCount
        )
        
        if BasicAuthCredentialsManager.validDomains.contains(host) {
          BasicAuthCredentialsManager.setCredential(origin: origin, credential: credentials.credentials)
        }
        
        return (.useCredential, credentials.credentials)
      } catch {
        return (.rejectProtectionSpace, nil)
      }
    }.value
  }

  public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    guard let tab = tab(for: webView) else { return }
    // Set the committed url which will also set tab.url
    tab.committedURL = webView.url
    
    DispatchQueue.main.async {
      // Server Trust and URL is also updated in didCommit
      // However, WebKit does NOT trigger the `serverTrust` observer when the URL changes, but the trust has not.
      // So manually trigger it with the current trust.
      self.observeValue(forKeyPath: KVOConstants.serverTrust.keyPath,
                        of: webView,
                        change: [.newKey: webView.serverTrust, .kindKey: 1],
                        context: nil)
    }
    
    // Need to evaluate Night mode script injection after url is set inside the Tab
    tab.nightMode = Preferences.General.nightModeEnabled.value
    tab.clearSolanaConnectedAccounts()
    
    // Providers need re-initialized when changing origin to align with desktop in
    // `BraveContentBrowserClient::RegisterBrowserInterfaceBindersForFrame`
    // https://github.com/brave/brave-core/blob/1.52.x/browser/brave_content_browser_client.cc#L608
    if let provider = braveCore.braveWalletAPI.ethereumProvider(with: tab, isPrivateBrowsing: tab.isPrivate) {
      // The Ethereum provider will fetch allowed accounts from it's delegate (the tab)
      // on initialization. Fetching allowed accounts requires the origin; so we need to
      // initialize after `commitedURL` / `url` are updated above
      tab.walletEthProvider = provider
      tab.walletEthProvider?.`init`(tab)
    }
    if let provider = braveCore.braveWalletAPI.solanaProvider(with: tab, isPrivateBrowsing: tab.isPrivate) {
      tab.walletSolProvider = provider
      tab.walletSolProvider?.`init`(tab)
    }

    rewards.reportTabNavigation(tabId: tab.rewardsId)

    if tabManager.selectedTab === tab {
      updateUIForReaderHomeStateForTab(tab)
    }
  }

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    if let tab = tabManager[webView] {
      
      // Deciding whether to inject app's IAP receipt for Brave SKUs or not
      if let url = tab.url,
          let braveSkusHelper = BraveSkusWebHelper(for: url),
          let receiptData = braveSkusHelper.receiptData,
          !tab.isPrivate {
        tab.injectLocalStorageItem(key: receiptData.key, value: receiptData.value)
      }

      // Second attempt to inject results to the BraveSearch.
      // This will be called if we got fallback results faster than
      // the page navigation.
      if let braveSearchManager = tab.braveSearchManager {
        // Fallback results are ready before navigation finished,
        // they must be injected here.
        if !braveSearchManager.fallbackQueryResultsPending {
          tab.injectResults()
        }
      } else {
        // If not applicable, null results must be injected regardless.
        // The website waits on us until this is called with either results or null.
        tab.injectResults()
      }

      navigateInTab(tab: tab, to: navigation)
      if let url = tab.url, tab.shouldClassifyLoadsForAds {
        rewards.reportTabUpdated(
          tab: tab,
          url: url,
          isSelected: tabManager.selectedTab == tab,
          isPrivate: privateBrowsingManager.isPrivateBrowsing
        )
      }
      
      Task {
        await tab.updateEthereumProperties()
        await tab.updateSolanaProperties()
      }
      
      tab.reportPageLoad(to: rewards, redirectionURLs: tab.redirectURLs)
      tab.redirectURLs = []
      if webView.url?.isLocal == false {
        // Reset should classify
        tab.shouldClassifyLoadsForAds = true
        // Set rewards inter site url as new page load url.
        rewardsXHRLoadURL = webView.url
      }
      
      if tab.walletEthProvider != nil {
        tab.emitEthereumEvent(.connect)
      }
    }

    // Added this method to determine long press menu actions better
    // Since these actions are depending on tabmanager opened WebsiteCount
    updateToolbarUsingTabManager(tabManager)
    
    recordFinishedPageLoadP3A()
  }

  public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
    guard let tab = tab(for: webView), let url = webView.url, rewards.isEnabled else { return }
    tab.redirectURLs.append(url)
  }
  
  /// Invoked when an error occurs while starting to load data for the main frame.
  public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    // Ignore the "Frame load interrupted" error that is triggered when we cancel a request
    // to open an external application and hand it over to UIApplication.openURL(). The result
    // will be that we switch to the external app, for example the app store, while keeping the
    // original web page in the tab instead of replacing it with an error page.
    var error = error as NSError
    if error.domain == "WebKitErrorDomain" && error.code == 102 {
      return
    }

    if checkIfWebContentProcessHasCrashed(webView, error: error) {
      return
    }
    
    if let tab = tabManager[webView], let sslPinningError = tab.sslPinningError {
      error = sslPinningError as NSError
    }

    if error.code == Int(CFNetworkErrors.cfurlErrorCancelled.rawValue) {
      if let tab = tabManager[webView], tab === tabManager.selectedTab {
        updateToolbarCurrentURL(tab.url?.displayURL)
        updateWebViewPageZoom(tab: tab)
      }
      return
    }

    if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
      ErrorPageHelper(certStore: profile.certStore).loadPage(error, forUrl: url, inWebView: webView)
      // Submitting same errornous URL using toolbar will cause progress bar get stuck
      // Reseting the progress bar in case there is an error is necessary
      topToolbar.hideProgressBar()

      // If the local web server isn't working for some reason (Brave cellular data is
      // disabled in settings, for example), we'll fail to load the session restore URL.
      // We rely on loading that page to get the restore callback to reset the restoring
      // flag, so if we fail to load that page, reset it here.
      if InternalURL(url)?.aboutComponent == "sessionrestore" {
        tabManager.allTabs.filter { $0.webView == webView }.first?.restoring = false
      }
    }
  }
}

// MARK: WKNavigationDelegateHelper

extension BrowserViewController {
  fileprivate func recordFinishedPageLoadP3A() {
    var storage = P3ATimedStorage<Int>.pagesLoadedStorage
    storage.add(value: 1, to: Date())
    UmaHistogramRecordValueToBucket(
      "Brave.Core.PagesLoaded",
      buckets: [
        0,
        .r(1...10),
        .r(11...50),
        .r(51...100),
        .r(101...500),
        .r(501...1000),
        .r(1001...),
      ],
      value: storage.combinedValue
    )
  }
  
  private func tab(for webView: WKWebView) -> Tab? {
    tabManager[webView] ?? (webView as? TabWebView)?.tab
  }
  
  private func handleExternalURL(
    _ url: URL,
    tab: Tab?,
    navigationAction: WKNavigationAction,
    openedURLCompletionHandler: ((Bool) -> Void)? = nil
  ) {
    // Do not open external links for child tabs automatically
    // The user must tap on the link to open it.
    if tab?.parent != nil && navigationAction.navigationType != .linkActivated {
      return
    }
    
    // Check if the current url of the caller has changed
    if let domain = tab?.url?.baseDomain,
       domain != tab?.externalAppURLDomain {
      tab?.externalAppAlertCounter = 0
      tab?.isExternalAppAlertSuppressed = false
    }
    tab?.externalAppURLDomain = tab?.url?.baseDomain
    
    // Do not try to present over existing warning
    if tab?.isExternalAppAlertPresented == true || tab?.isExternalAppAlertSuppressed == true {
      return
    }

    // We do not schemes to be opened externally when called from subframes.
    // And external dialog should not be shown for non-active tabs #6687 - #7835
    
    // Check navigation action is from main frame as first step
    let isMainFrame = navigationAction.targetFrame?.isMainFrame == true

    // Check user trying to open on NTP like external link browsing
    var isAboutHome = false
    if let url = tab?.url {
      isAboutHome = InternalURL(url)?.isAboutHomeURL == true
    }

    // Finally check non-active tab
    let isNonActiveTab = isAboutHome ? false : tab?.url?.host != topToolbar.currentURL?.host

    if !isMainFrame || isNonActiveTab {
      return
    }
    
    var alertTitle = Strings.openExternalAppURLGenericTitle

    if let displayHost = tab?.url?.withoutWWW.host {
      alertTitle = String(format: Strings.openExternalAppURLTitle, displayHost)
    }
    
    // Handling condition when Tab is empty when handling an external URL we should remove the tab once the user decides
    let removeTabIfEmpty = { [weak self] in
      if let tab = tab, tab.url == nil {
        self?.tabManager.removeTab(tab)
      }
    }
    
    // Show the external sceheme invoke alert
    func showExternalSchemeAlert(isSuppressActive: Bool) {
      // Check if active controller is bvc otherwise do not show show external sceheme alerts
      guard shouldShowExternalSchemeAlert() else { return }
      
      view.endEditing(true)
      tab?.isExternalAppAlertPresented = true

      let popup = AlertPopupView(
        imageView: nil,
        title: alertTitle,
        message: String(format: Strings.openExternalAppURLMessage, url.relativeString),
        titleWeight: .semibold,
        titleSize: 21
      )
      if isSuppressActive {
        popup.addButton(title: Strings.suppressAlertsActionTitle, type: .destructive) { [weak tab] () -> PopupViewDismissType in
          tab?.isExternalAppAlertSuppressed = true
          return .flyDown
        }
      } else {
        popup.addButton(title: Strings.openExternalAppURLDontAllow) { [weak tab] () -> PopupViewDismissType in
          removeTabIfEmpty()
          tab?.isExternalAppAlertPresented = false
          return .flyDown
        }
      }
      popup.addButton(title: Strings.openExternalAppURLAllow, type: .primary) { [weak tab] () -> PopupViewDismissType in
        UIApplication.shared.open(url, options: [:], completionHandler: openedURLCompletionHandler)
        removeTabIfEmpty()
        tab?.isExternalAppAlertPresented = false
        return .flyDown
      }
      popup.showWithType(showType: .flyUp)
    }
    
    func shouldShowExternalSchemeAlert() -> Bool {
      guard let rootVC = currentScene?.browserViewController else {
        return false
      }
      
      func topViewController(startingFrom viewController: UIViewController) -> UIViewController {
        var top = viewController
        if let navigationController = top as? UINavigationController,
          let vc = navigationController.visibleViewController {
          return topViewController(startingFrom: vc)
        }
        if let tabController = top as? UITabBarController,
          let vc = tabController.selectedViewController {
          return topViewController(startingFrom: vc)
        }
        while let next = top.presentedViewController {
          top = next
        }
        return top
      }
      
      let isTopController = self == topViewController(startingFrom: rootVC)
      let isTopWindow = view.window?.isKeyWindow == true
      return isTopController && isTopWindow
    }

    tab?.externalAppAlertCounter += 1
    showExternalSchemeAlert(isSuppressActive: tab?.externalAppAlertCounter ?? 0 > 2)
  }
}

// MARK: WKUIDelegate

extension BrowserViewController: WKUIDelegate {
  public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    guard let parentTab = tabManager[webView] else { return nil }

    guard !navigationAction.isInternalUnprivileged,
          let navigationURL = navigationAction.request.url,
          navigationURL.shouldRequestBeOpenedAsPopup()
    else {
      print("Denying popup from request: \(navigationAction.request)")
      return nil
    }

    if let currentTab = tabManager.selectedTab {
      screenshotHelper.takeScreenshot(currentTab)
    }

    // If the page uses `window.open()` or `[target="_blank"]`, open the page in a new tab.
    // IMPORTANT!!: WebKit will perform the `URLRequest` automatically!! Attempting to do
    // the request here manually leads to incorrect results!!
    let newTab = tabManager.addPopupForParentTab(parentTab, configuration: configuration)

    newTab.url = URL(string: "about:blank")
    
    toolbarVisibilityViewModel.toolbarState = .expanded

    return newTab.webView
  }
  
  public func webViewDidClose(_ webView: WKWebView) {
    guard let tab = tabManager[webView] else { return }
    tabManager.addTabToRecentlyClosed(tab)
    tabManager.removeTab(tab)
  }

  fileprivate func shouldDisplayJSAlertForWebView(_ webView: WKWebView) -> Bool {
    // Only display a JS Alert if we are selected and there isn't anything being shown
    return ((tabManager.selectedTab == nil ? false : tabManager.selectedTab!.webView == webView)) && (self.presentedViewController == nil)
  }

  public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
    var messageAlert = MessageAlert(message: message, frame: frame, completionHandler: completionHandler, suppressHandler: nil)
    handleAlert(webView: webView, alert: &messageAlert) {
      completionHandler()
    }
  }

  public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
    var confirmAlert = ConfirmPanelAlert(message: message, frame: frame, completionHandler: completionHandler, suppressHandler: nil)
    handleAlert(webView: webView, alert: &confirmAlert) {
      completionHandler(false)
    }
  }

  public func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
    var textInputAlert = TextInputAlert(message: prompt, frame: frame, completionHandler: completionHandler, defaultText: defaultText, suppressHandler: nil)
    handleAlert(webView: webView, alert: &textInputAlert) {
      completionHandler(nil)
    }
  }

  func suppressJSAlerts(webView: WKWebView) {
    let script = """
      window.alert=window.confirm=window.prompt=function(n){},
      [].slice.apply(document.querySelectorAll('iframe')).forEach(function(n){if(n.contentWindow != window){n.contentWindow.alert=n.contentWindow.confirm=n.contentWindow.prompt=function(n){}}})
      """
    webView.evaluateSafeJavaScript(functionName: script, contentWorld: .defaultClient, asFunction: false)
  }

  func handleAlert<T: JSAlertInfo>(webView: WKWebView, alert: inout T, completionHandler: @escaping () -> Void) {
    guard let promptingTab = tabManager[webView], !promptingTab.blockAllAlerts else {
      suppressJSAlerts(webView: webView)
      tabManager[webView]?.cancelQueuedAlerts()
      completionHandler()
      return
    }
    promptingTab.alertShownCount += 1
    let suppressBlock: JSAlertInfo.SuppressHandler = { [unowned self] suppress in
      if suppress {
        func suppressDialogues(_: UIAlertAction) {
          self.suppressJSAlerts(webView: webView)
          promptingTab.blockAllAlerts = true
          self.tabManager[webView]?.cancelQueuedAlerts()
          completionHandler()
        }
        // Show confirm alert here.
        let suppressSheet = UIAlertController(title: nil, message: Strings.suppressAlertsActionMessage, preferredStyle: .actionSheet)
        suppressSheet.addAction(UIAlertAction(title: Strings.suppressAlertsActionTitle, style: .destructive, handler: suppressDialogues))
        suppressSheet.addAction(
          UIAlertAction(
            title: Strings.cancelButtonTitle, style: .cancel,
            handler: { _ in
              completionHandler()
            }))
        if UIDevice.current.userInterfaceIdiom == .pad, let popoverController = suppressSheet.popoverPresentationController {
          popoverController.sourceView = self.view
          popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
          popoverController.permittedArrowDirections = []
        }
        self.present(suppressSheet, animated: true)
      } else {
        completionHandler()
      }
    }
    alert.suppressHandler = promptingTab.alertShownCount > 1 ? suppressBlock : nil
    if shouldDisplayJSAlertForWebView(webView) {
      let controller = alert.alertController()
      controller.delegate = self
      present(controller, animated: true)
    } else {
      promptingTab.queueJavascriptAlertPrompt(alert)
    }
  }

  func checkIfWebContentProcessHasCrashed(_ webView: WKWebView, error: NSError) -> Bool {
    if error.code == WKError.webContentProcessTerminated.rawValue && error.domain == "WebKitErrorDomain" {
      print("WebContent process has crashed. Trying to reload to restart it.")
      webView.reload()
      return true
    }

    return false
  }

  public func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo, completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {

    // Only show context menu for valid links such as `http`, `https`, `data`. Safari does not show it for anything else.
    // This is because you cannot open `javascript:something` URLs in a new page, or share it, or anything else.
    guard let url = elementInfo.linkURL, url.isWebPage() else { return completionHandler(UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: nil)) }

    let actionProvider: UIContextMenuActionProvider = { _ -> UIMenu? in
      var actions = [UIAction]()

      if let currentTab = self.tabManager.selectedTab {
        let tabType = currentTab.type

        if !tabType.isPrivate {
          let openNewTabAction = UIAction(
            title: Strings.openNewTabButtonTitle,
            image: UIImage(systemName: "plus")
          ) { _ in
            self.addTab(url: url, inPrivateMode: false, currentTab: currentTab)
          }

          openNewTabAction.accessibilityLabel = "linkContextMenu.openInNewTab"
          actions.append(openNewTabAction)
        }

        let openNewPrivateTabAction = UIAction(
          title: Strings.openNewPrivateTabButtonTitle,
          image: UIImage(named: "private_glasses", in: .module, compatibleWith: nil)!.template
        ) { _ in
          if !tabType.isPrivate, Preferences.Privacy.privateBrowsingLock.value {
            self.askForLocalAuthentication { [weak self] success, error in
              if success {
                self?.addTab(url: url, inPrivateMode: true, currentTab: currentTab)
              }
            }
          } else {
            self.addTab(url: url, inPrivateMode: true, currentTab: currentTab)
          }
        }
        openNewPrivateTabAction.accessibilityLabel = "linkContextMenu.openInNewPrivateTab"
        
        actions.append(openNewPrivateTabAction)
        
        if UIApplication.shared.supportsMultipleScenes {
          if !tabType.isPrivate {
            let openNewWindowAction = UIAction(
              title: Strings.openInNewWindowTitle,
              image: UIImage(braveSystemNamed: "leo.window")
            ) { _ in
              self.openInNewWindow(url: url, isPrivate: false)
            }
            
            openNewWindowAction.accessibilityLabel = "linkContextMenu.openInNewWindow"
            actions.append(openNewWindowAction)
          }
          
          let openNewPrivateWindowAction = UIAction(
            title: Strings.openInNewPrivateWindowTitle,
            image: UIImage(braveSystemNamed: "leo.window.tab-private")
          ) { _ in
            if !tabType.isPrivate, Preferences.Privacy.privateBrowsingLock.value {
              self.askForLocalAuthentication { [weak self] success, error in
                if success {
                  self?.openInNewWindow(url: url, isPrivate: true)
                }
              }
            } else {
              self.openInNewWindow(url: url, isPrivate: true)
            }
          }
          
          openNewPrivateWindowAction.accessibilityLabel = "linkContextMenu.openInNewPrivateWindow"
          actions.append(openNewPrivateWindowAction)
        }

        let copyAction = UIAction(
          title: Strings.copyLinkActionTitle,
          image: UIImage(systemName: "doc.on.doc"),
          handler: UIAction.deferredActionHandler { _ in
            UIPasteboard.general.url = url as URL
          }
        )
        copyAction.accessibilityLabel = "linkContextMenu.copyLink"
        actions.append(copyAction)
        
        let copyCleanLinkAction = UIAction(
          title: Strings.copyCleanLink,
          image: UIImage(braveSystemNamed: "leo.broom"),
          handler: UIAction.deferredActionHandler { _ in
            let service = URLSanitizerServiceFactory.get(privateMode: currentTab.isPrivate)
            let cleanedURL = service?.sanitizeURL(url) ?? url
            UIPasteboard.general.url = cleanedURL
          }
        )
        copyCleanLinkAction.accessibilityLabel = "linkContextMenu.copyCleanLink"
        actions.append(copyCleanLinkAction)

        if let braveWebView = webView as? BraveWebView {
          let shareAction = UIAction(
            title: Strings.shareLinkActionTitle,
            image: UIImage(systemName: "square.and.arrow.up")
          ) { _ in
            let touchPoint = braveWebView.lastHitPoint
            let touchRect = CGRect(origin: touchPoint, size: .zero)

            // TODO: Find a way to add fixes #3323 and #2961 here:
            // Normally we use `tab.temporaryDocument` for the downloaded file on the tab.
            // `temporaryDocument` returns the downloaded file to disk on the current tab.
            // Using a downloaded file url results in having functions like "Save to files" available.
            // It also attaches the file (image, pdf, etc) and not the url to emails, slack, etc.
            // Since this is **not** a tab but a standalone web view, the downloaded temporary file is **not** available.
            // This results in the fixes for #3323 and #2961 not being included in this share scenario.
            // This is not a regression, we simply never handled this scenario in both fixes.
            // Some possibile fixes include:
            // - Detect the file type and download it if necessary and don't rely on the `tab.temporaryDocument`.
            // - Add custom "Save to file" functionality (needs investigation).
            self.presentActivityViewController(
              url, sourceView: braveWebView,
              sourceRect: touchRect,
              arrowDirection: .any)
          }

          shareAction.accessibilityLabel = "linkContextMenu.share"

          actions.append(shareAction)
        }

        let linkPreview = Preferences.General.enableLinkPreview.value

        let linkPreviewTitle = linkPreview ? Strings.hideLinkPreviewsActionTitle : Strings.showLinkPreviewsActionTitle
        let linkPreviewAction = UIAction(title: linkPreviewTitle, image: UIImage(systemName: "eye.fill")) { _ in
          Preferences.General.enableLinkPreview.value.toggle()
        }

        actions.append(linkPreviewAction)
      }

      return UIMenu(title: url.absoluteString.truncate(length: 100), children: actions)
    }

    let linkPreview: UIContextMenuContentPreviewProvider? = { [unowned self] in
      if let tab = tabManager.tabForWebView(webView) {
        return LinkPreviewViewController(url: url, for: tab, browserController: self)
      }
      return nil
    }

    let linkPreviewProvider = Preferences.General.enableLinkPreview.value ? linkPreview : nil
    let config = UIContextMenuConfiguration(
      identifier: nil, previewProvider: linkPreviewProvider,
      actionProvider: actionProvider)

    completionHandler(config)
  }

  public func webView(_ webView: WKWebView, contextMenuForElement elementInfo: WKContextMenuElementInfo, willCommitWithAnimator animator: UIContextMenuInteractionCommitAnimating) {
    guard let url = elementInfo.linkURL else { return }
    webView.load(URLRequest(url: url))
  }

  fileprivate func addTab(url: URL, inPrivateMode: Bool, currentTab: Tab) {
    let tab = self.tabManager.addTab(URLRequest(url: url), afterTab: currentTab, isPrivate: inPrivateMode)
    if inPrivateMode && !privateBrowsingManager.isPrivateBrowsing {
      self.tabManager.selectTab(tab)
    } else {
      // We're not showing the top tabs; show a toast to quick switch to the fresh new tab.
      let toast = ButtonToast(
        labelText: Strings.contextMenuButtonToastNewTabOpenedLabelText, buttonText: Strings.contextMenuButtonToastNewTabOpenedButtonText,
        completion: { buttonPressed in
          if buttonPressed {
            self.tabManager.selectTab(tab)
          }
        })
      self.show(toast: toast)
    }
    self.toolbarVisibilityViewModel.toolbarState = .expanded
  }
  
  /// Get a possible redirect request from debouncing or query param stripping
  private func getInternalRedirect(from navigationAction: WKNavigationAction, in tab: Tab, domainForMainFrame: Domain) -> URLRequest? {
    guard let requestURL = navigationAction.request.url else { return nil }
    
    // For main frame only and if shields are enabled
    guard requestURL.isWebPage(includeDataURIs: false),
          domainForMainFrame.isShieldExpected(.AdblockAndTp, considerAllShieldsOption: true),
          navigationAction.targetFrame?.isMainFrame == true
    else { return nil }
    
    // Handle Debounce
    // Only if the site (etld+1) changes
    // We also only handle `http` and `https` requests
    // Lets get the redirect chain.
    // Then we simply get all elements up until the user allows us to redirect
    // (i.e. appropriate settings are enabled for that redirect rule)
    if Preferences.Shields.autoRedirectTrackingURLs.value,
       let currentURL = tab.webView?.url,
       currentURL.baseDomain != requestURL.baseDomain {
      let redirectChain = DebouncingService.shared
        .redirectChain(for: requestURL)
        .contiguousUntil { _, rule in
          return rule.preferences.allSatisfy { pref in
            switch pref {
            case .deAmpEnabled:
              return Preferences.Shields.autoRedirectAMPPages.value
            }
          }
        }
      
      // Once we check the redirect chain only need the last (final) url from our redirect chain
      if let redirectURL = redirectChain.last?.url {
        // For now we only allow the `Referer`. The browser will add other headers during navigation.
        var modifiedRequest = URLRequest(url: redirectURL)
        
        // Also strip query params if debouncing
        modifiedRequest = modifiedRequest.stripQueryParams(
          initiatorURL: tab.committedURL,
          redirectSourceURL: requestURL,
          isInternalRedirect: false
        ) ?? modifiedRequest
        
        for (headerKey, headerValue) in navigationAction.request.allHTTPHeaderFields ?? [:] {
          guard headerKey == "Referer" else { continue }
          modifiedRequest.setValue(headerValue, forHTTPHeaderField: headerKey)
        }
        
        return modifiedRequest
      }
    }
    
    // Handle query param stripping
    return navigationAction.request.stripQueryParams(
      initiatorURL: tab.committedURL,
      redirectSourceURL: tab.redirectSourceURL,
      isInternalRedirect: tab.isInternalRedirect
    )
  }
}

extension P3ATimedStorage where Value == Int {
  fileprivate static var pagesLoadedStorage: Self { .init(name: "paged-loaded", lifetimeInDays: 7) }
}

private extension URLRequest {
  /// Strip any query params in the request and return a new request if anything is stripped.
  ///
  /// The `isInternalRedirect` is a true value whenever we redirected the user for debouncing or query-stripping.
  /// It's an optimization because we assume that we stripped and debounced the user fully so there should be no further stripping on the next iteration.
  ///
  /// - Parameters:
  ///   - initiatorURL: The url page the user is coming from before any redirects
  ///   - redirectSourceURL: The last redirect url that happened (the true page the user is coming from)
  ///   - isInternalRedirect: Identifies if we have internally redirected or not. More info in the description
  /// - Returns: A modified request if any stripping is to occur.
  func stripQueryParams(initiatorURL: URL?, redirectSourceURL: URL?, isInternalRedirect: Bool) -> URLRequest? {
    guard let requestURL = url,
          let requestMethod = httpMethod
    else { return nil }
    
    guard let strippedURL = (requestURL as NSURL).applyingQueryFilter(
      initiatorURL: initiatorURL,
      redirectSourceURL: redirectSourceURL,
      requestMethod: requestMethod,
      isInternalRedirect: isInternalRedirect
    ) else { return nil }
    
    var modifiedRequest = self
    modifiedRequest.url = strippedURL
    return modifiedRequest
  }
}
