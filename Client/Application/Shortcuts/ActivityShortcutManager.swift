// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Shared
import Data
import BraveShared
import Intents
import CoreSpotlight
import MobileCoreServices

private let log = Logger.browserLogger

/// Shortcut Activity Types and detailed information to create and perform actions
enum ActivityType: String {
    case newTab = "NewTab"
    case newPrivateTab = "NewPrivateTab"
    case clearBrowsingHistory = "ClearBrowsingHistory"
    case enableBraveVPN = "EnableBraveVPN"
    case openBraveNews = "OpenBraveNews"
    case openPlayList = "OpenPlayList"

    var identifier: String {
        return "\(Bundle.main.bundleIdentifier ?? "").\(self.rawValue)"
    }
    
    /// The activity title for designated  type
    var title: String {
        switch self {
            case .newTab:
                return Strings.Shortcuts.activityTypeNewTabTitle
            case .newPrivateTab:
                return Strings.Shortcuts.activityTypeNewPrivateTabTitle
            case .clearBrowsingHistory:
                return Strings.Shortcuts.activityTypeClearHistoryTitle
            case .enableBraveVPN:
                return Strings.Shortcuts.activityTypeEnableVPNTitle
            case .openBraveNews:
                return Strings.Shortcuts.activityTypeOpenBraveNewsTitle
            case .openPlayList:
                return Strings.Shortcuts.activityTypeOpenPlaylistTitle
        }
    }
    
    /// The content description for designated activity  type
    var description: String {
        switch self {
            case .newTab, .newPrivateTab:
                return Strings.Shortcuts.activityTypeTabDescription
            case .clearBrowsingHistory:
                return Strings.Shortcuts.activityTypeClearHistoryDescription
            case .enableBraveVPN:
                return Strings.Shortcuts.activityTypeEnableVPNDescription
            case .openBraveNews:
                return Strings.Shortcuts.activityTypeBraveNewsDescription
            case .openPlayList:
                return Strings.Shortcuts.activityTypeOpenPlaylistDescription
        }
    }
    
    /// The phrase suggested to the user when they create a shortcut for the activity
    var suggestedPhrase: String {
        switch self {
            case .newTab:
                return Strings.Shortcuts.activityTypeNewTabSuggestedPhrase
            case .newPrivateTab:
                return Strings.Shortcuts.activityTypeNewPrivateTabSuggestedPhrase
            case .clearBrowsingHistory:
                return Strings.Shortcuts.activityTypeClearHistorySuggestedPhrase
            case .enableBraveVPN:
                return Strings.Shortcuts.activityTypeEnableVPNSuggestedPhrase
            case .openBraveNews:
                return Strings.Shortcuts.activityTypeOpenBraveNewsSuggestedPhrase
            case .openPlayList:
                return Strings.Shortcuts.activityTypeOpenPlaylistSuggestedPhrase
        }
    }
}

/// Singleton Manager handles creation and action for Activities
class ActivityShortcutManager: NSObject {
    
    /// Custom Intent Types
    enum IntentType {
        case openWebsite
        case openHistory
        case openBookmarks
    }

    // MARK: Lifecycle
    
    static var shared = ActivityShortcutManager()
    
    // MARK: Activity Creation Methods
    
    public func createShortcutActivity(type: ActivityType) -> NSUserActivity {
        let attributes = CSSearchableItemAttributeSet(itemContentType: kUTTypeItem as String)
        attributes.contentDescription = type.description
        
        let activity = NSUserActivity(activityType: type.identifier)
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier(type.identifier)
        
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        
        activity.title = type.title
        activity.suggestedInvocationPhrase = type.suggestedPhrase
        activity.contentAttributeSet = attributes

        return activity
    }

    // MARK: Activity Action Methods

    public func performShortcutActivity(type: ActivityType, using bvc: BrowserViewController) {
        switch type {
            case .newTab:
                bvc.openBlankNewTab(attemptLocationFieldFocus: true, isPrivate: false)
            case .newPrivateTab:
                bvc.openBlankNewTab(attemptLocationFieldFocus: true, isPrivate: true)
            case .clearBrowsingHistory:
                bvc.clearHistoryAndOpenNewTab()
            case .enableBraveVPN:
                bvc.openBlankNewTab(attemptLocationFieldFocus: true, isPrivate: false)

                switch BraveVPN.vpnState {
                    case .notPurchased, .purchased, .expired:
                        guard let enableVPNController = BraveVPN.vpnState.enableVPNDestinationVC else { return }
                    
                        bvc.openInsideSettingsNavigation(with: enableVPNController)
                    case .installed(let connected):
                        if !connected {
                            BraveVPN.reconnect()
                        }
                }
            case .openBraveNews:
                bvc.openBlankNewTab(attemptLocationFieldFocus: true, isPrivate: false)

                guard let newTabPageController = bvc.tabManager.selectedTab?.newTabPageViewController else { return }
                newTabPageController.scrollToBraveNews()
            case .openPlayList:
                let playlistController = (UIApplication.shared.delegate as? AppDelegate)?.playlistRestorationController ?? PlaylistViewController()
                playlistController.modalPresentationStyle = .fullScreen
                
                bvc.present(playlistController, animated: true)
        }
    }
    
    // MARK: Intent Creation Methods
    
    private func createCustomIntent(for type: IntentType, with urlString: String) -> INIntent {
        switch type {
            case .openWebsite:
                let intent = OpenWebsiteIntent()
                intent.websiteURL = urlString
                intent.suggestedInvocationPhrase = Strings.Shortcuts.customIntentOpenWebsiteSuggestedPhrase
                
                return intent
            case .openHistory:
                let intent = OpenHistoryWebsiteIntent()
                intent.websiteURL = urlString
                intent.suggestedInvocationPhrase = Strings.Shortcuts.customIntentOpenHistorySuggestedPhrase
                
                return intent
            case .openBookmarks:
                let intent = OpenBookmarkWebsiteIntent()
                intent.websiteURL = urlString
                intent.suggestedInvocationPhrase = Strings.Shortcuts.customIntentOpenBookmarkSuggestedPhrase
                
                return intent
        }
    }
    
    // MARK: Intent Donation Methods
    
    public func donateCustomIntent(for type: IntentType, with urlString: String) {
        let intent = createCustomIntent(for: type, with: urlString)

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            guard let error = error else {
                return
            }
            
            log.error("Failed to donate shorcut open website, error: \(error)")
        }
    }
}
