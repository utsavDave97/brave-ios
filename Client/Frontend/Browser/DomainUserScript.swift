// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Shared
import BraveShared
import WebKit

private let log = Logger.browserLogger

enum DomainUserScript: CaseIterable {
  case braveSearchHelper
  case braveTalkHelper
  case braveSkus
  case bravePlaylistFolderSharingHelper

  /// Initialize this script with a URL
  init?(for url: URL) {
    // First we look for an exact domain match
    if let host = url.host, let found = Self.allCases.first(where: { $0.associatedDomains.contains(host) }) {
      self = found
      return
    }

    // If no matches, we look for a baseDomain (eTLD+1) match.
    if let baseDomain = url.baseDomain, let found = Self.allCases.first(where: { $0.associatedDomains.contains(baseDomain) }) {
      self = found
      return
    }

    return nil
  }

  /// The domains associated with this script.
  var associatedDomains: Set<String> {
    switch self {
    case .braveSearchHelper:
      return Set(["search.brave.com", "search-dev.brave.com", "search.brave.software"])
    case .braveTalkHelper:
      return Set(["talk.brave.com", "beta.talk.brave.com",
                 "talk.bravesoftware.com", "beta.talk.bravesoftware.com",
                 "dev.talk.brave.software", "beta.talk.brave.software",
                 "talk.brave.software"])
    case .bravePlaylistFolderSharingHelper:
      return Set(["playlist.bravesoftware.com", "playlist.brave.com"])
    case .braveSkus:
      return Set(["account.brave.com",
                   "account.bravesoftware.com",
                   "account.brave.software"])
    }
  }
  
  var fileName: String {
    switch self {
    case .braveSearchHelper: return "BraveSearchScript"
    case .braveTalkHelper: return "BraveTalkScript"
    case .bravePlaylistFolderSharingHelper: return "PlaylistFolderSharingScript"
    case .braveSkus: return "BraveSkusScript"
    }
  }

  func loadScript() throws -> String {
    guard let path = Bundle.current.path(forResource: fileName, ofType: "js") else {
      assertionFailure("Cannot load script. This should not happen as it's part of the codebase")
      throw ScriptLoadFailure.notFound
    }

    return try String(contentsOfFile: path)
  }
}
