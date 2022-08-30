/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import os.log
import OSLog

/// A logging system used in the app. Based on os.log classes.
public struct Log {}

public extension Log {
  /// To make it easier to grab correct logs, there's few categories you can choose from.
  /// New categories can be added, based on needs for your module.
  enum Category: String {
    case main = "main"
    case braveCore = "brave-core"
    case adsRewards = "ads-rewards"
    case legacy = "legacy"
  }
  
  /// Subsystem name. All Brave logs should use this subsystem.
  private static let subsystem = "com.brave.ios"
  
  /// Main logger of the app. Should be used for most things you want to log.
  static let main = Logger(subsystem: subsystem, category: Category.main.rawValue)
  
  /// This log category is used to capture logs from the Brave-Core framework.
  /// Avoid calling this log from other places unless the code belongs close to the Brave-Core framework functionality.
  static let braveCore = Logger(subsystem: subsystem, category: Category.braveCore.rawValue)
  
  static let adsRewards = Logger(subsystem: subsystem, category: Category.adsRewards.rawValue)
  
  /// Used in legacy places, in code we inherited from Firefox, should not be used elsewhere.
  static let legacy = Logger(subsystem: subsystem, category: Category.legacy.rawValue)
  
  /// Allows you to export a log for a given category as a string array.
  /// Returns empty array in case of error.
  /// This method is available only for iOS 15+ due to api limitations.
  @available(iOS 15.0, *)
  static func export(category: Category) -> [String] {
    do {
      let formatter = DateFormatter()
      formatter.dateStyle = .short
      formatter.timeStyle = .short
      
      let store = try OSLogStore(scope: .currentProcessIdentifier)
      let entries = try store.getEntries()
        .compactMap { $0 as? OSLogEntryLog }
        .filter { $0.category == category.rawValue && $0.subsystem == subsystem }
        .map { "\(formatter.string(from: $0.date)): \($0.composedMessage)" }
      
      return entries
    } catch {
      assertionFailure("Failed to export logs for: \(category.rawValue)")
      return []
    }
  }
  
  /// The old log system was based on XCGLogger with a rolling file saved to disk.
  /// This method removes old entries of that old log implementation.
  static func removeLegacyLogs() {
    let fileManager = FileManager.default
    
    guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      return
    }
    
    let logDir = cacheDir.appendingPathComponent("Logs")

    if !fileManager.fileExists(atPath: logDir.path) {
      return
    }

    do {
      try fileManager.removeItem(at: logDir)
    } catch {
      Log.main.error("\(error.localizedDescription, privacy: .public)")
    }
  }
}
