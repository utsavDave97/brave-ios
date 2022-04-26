// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import WebKit
import Data
import BraveShared
import Shared
import SwiftUI
import BraveUI

private let log = Logger.browserLogger

private struct Manifest: Codable {
  // Required
  let manifestVersion: Double
  let name: String
  let version: String
  let updateUrl: String
  
  // Recommended
  let action: Action?
  let defaultLocale: String?
  let description: String?
  let icons: Icons?
  
  // Optional
  let author: String?
  let automation: String?
  let background: Background?
  
  let permissions: [String]?
  
  struct Action: Codable {
    
  }
  
  struct Icons: Codable {
    
  }
  
  struct Background: Codable {
    // Required
    let serviceWorker: String?
    
    // Optional
    let type: String?
  }
  
  private enum CodingKeys: String, CodingKey {
    case manifestVersion = "manifest_version"
    case name
    case version
    case updateUrl = "update_url"
    
    case action
    case defaultLocale = "default_locale"
    case description
    case icons
    
    case author
    case automation
    case background
    case permissions
  }
}

private struct ExtensionInfo: Codable {
  let id: String
  let manifest: Manifest
  let iconUrl: String?
  let localizedName: String?
  let locale: String?
  let appInstallBubble: Bool?
  let enableLauncher: Bool?
  let authUser: String?
  let esbAllowlist: Bool?
  let additionalProperties: [String: Any]?
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    
    let manifestString = try container.decode(String.self, forKey: .manifest)
    
    id = try container.decode(String.self, forKey: .id)
    manifest = try JSONDecoder().decode(Manifest.self, from: manifestString.data(using: .utf8)!)
    iconUrl = try container.decodeIfPresent(String.self, forKey: .iconUrl)
    localizedName = try container.decodeIfPresent(String.self, forKey: .localizedName)
    locale = try container.decodeIfPresent(String.self, forKey: .locale)
    appInstallBubble = try container.decodeIfPresent(Bool.self, forKey: .appInstallBubble)
    enableLauncher = try container.decodeIfPresent(Bool.self, forKey: .enableLauncher)
    authUser = try container.decodeIfPresent(String.self, forKey: .authUser)
    esbAllowlist = try container.decodeIfPresent(Bool.self, forKey: .esbAllowlist)
    additionalProperties = try? container.decodeAny([String: Any].self, forKey: .additionalProperties)
  }
  
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(manifest, forKey: .manifest)
    try container.encode(iconUrl, forKey: .iconUrl)
    try container.encode(localizedName, forKey: .localizedName)
    try container.encode(locale, forKey: .locale)
    try container.encode(appInstallBubble, forKey: .appInstallBubble)
    try container.encode(enableLauncher, forKey: .enableLauncher)
    try container.encode(authUser, forKey: .authUser)
    try container.encode(esbAllowlist, forKey: .esbAllowlist)
    try? container.encodeAny(additionalProperties, forKey: .additionalProperties)
  }
  
  private enum CodingKeys: String, CodingKey {
    case id
    case manifest
    case iconUrl
    case localizedName
    case locale
    case appInstallBubble
    case enableLauncher
    case authUser = "authuser"
    case esbAllowlist
    case additionalProperties
  }
}

class WebStorePrivateAPIHelper: NSObject, TabContentScript {
  private weak var tab: Tab?

  init(tab: Tab) {
    self.tab = tab
    super.init()
  }

  static func name() -> String {
    return "WebStorePrivateAPIHelper"
  }

  func scriptMessageHandlerName() -> String? {
    return "webStorePrivateAPIHelper_\(UserScriptManager.messageHandlerTokenString)"
  }
  
  func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
    guard let message = message.body as? [String: AnyHashable] else {
      replyHandler(nil, "Invalid Message")
      return
    }
    
    guard UserScriptManager.isMessageHandlerTokenMissing(in: message) else {
      replyHandler(nil, "Invalid Message")
      return
    }
    
    if message["name"] as? String == "beginInstallWithManifest3" {
      guard let data = message["data"] as? [String: AnyHashable] else {
        replyHandler(nil, "Invalid Message")
        return
      }

      do {
        let json = try JSONSerialization.data(withJSONObject: data, options: [.fragmentsAllowed])
        let model = try JSONDecoder().decode(ExtensionInfo.self, from: json)
        print(model)
        
        let browserController = tab?.webView?.window?.windowScene?.browserViewController
        
        var installView = WebStoreInstallUI(title: model.localizedName ?? "N/A",
                                            author: model.manifest.author ?? "N/A",
                                            iconURL: model.iconUrl ?? "N/A",
                                            permissions: model.manifest.permissions ?? []
        )
        
        installView.onCancel = { [replyHandler] in
          replyHandler(nil, "user_cancelled")
          browserController?.dismiss(animated: true, completion: nil)
        }
        
        installView.onInstall = {
          replyHandler(nil, nil)
          browserController?.dismiss(animated: true, completion: nil)
        }
        
        let controller = PopupViewController(rootView: installView).then {
          $0.isModalInPresentation = true
          $0.modalPresentationStyle = .overFullScreen
        }
        
        browserController?.present(controller, animated: true)
      } catch {
        log.error(error)
        replyHandler(nil, "Invalid Manifest")
      }
    } else {
      replyHandler("installable", nil)
    }
  }
}
