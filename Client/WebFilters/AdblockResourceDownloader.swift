// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import BraveCore
import Shared
import BraveShared

private let log = Logger.browserLogger

public class AdblockResourceDownloader {
  public static let shared = AdblockResourceDownloader()
  
  /// A boolean indicating if this is a first time load of this downloader so we only load cached data once
  private var initialLoad = true
  private let resourceDownloader: ResourceDownloader
  private let serialQueue = DispatchQueue(label: "com.brave.FilterListManager-dispatch-queue")

  init(networkManager: NetworkManager = NetworkManager()) {
    self.resourceDownloader = ResourceDownloader(networkManager: networkManager)
  }

  /// Initialized with year 1970 to force adblock fetch at first launch.
  private(set) var lastFetchDate = Date(timeIntervalSince1970: 0)

  public func startLoading() {
    guard initialLoad else { return }
    initialLoad = false
    
    Task {
      do {
        if let filterRulesData = try ResourceDownloader.data(for: .genericFilterRules) {
          let engine = await loadEngineFromResourceDownloader(data: filterRulesData)
          await set(genericEngine: engine)
        }
      } catch {
        log.error(error)
      }
      
      do {
        if let contentBlockerData = try ResourceDownloader.data(for: .genericContentBlockingBehaviors) {
          try await compileContentBlocker(data: contentBlockerData)
        }
      } catch {
        log.error(error)
      }
      
      await startFetching()
    }
  }

  @MainActor private func startFetching() {
    assertIsMainThread("Not on main thread")
    let now = Date()
    let fetchInterval = AppConstants.buildChannel.isPublic ? 6.hours : 10.minutes
    
    if now.timeIntervalSince(lastFetchDate) >= fetchInterval {
      lastFetchDate = now
      downloadFilterRules()
      downloadContentBlockingBehaviours()
    }
  }
  
  private func downloadFilterRules() {
    Task.detached(priority: .background) {
      do {
        let result = try await self.resourceDownloader.download(resource: .genericFilterRules)
        
        switch result {
        case .notModified:
          // No need to reload this
          break
        case .downloaded:
          guard let data = try ResourceDownloader.data(for: .genericFilterRules) else {
            assertionFailure("Should not happen. We just downloaded the data!")
            return
          }
          
          let engine = await self.loadEngineFromResourceDownloader(data: data)
          await self.set(genericEngine: engine)
        }
      } catch {
        log.error(error)
      }
    }
  }
  
  private func downloadContentBlockingBehaviours() {
    Task.detached(priority: .background) {
      do {
        let result = try await self.resourceDownloader.download(resource: .genericContentBlockingBehaviors)
        
        switch result {
        case .notModified:
          // No need to reload this
          break
        case .downloaded:
          guard let data = try ResourceDownloader.data(for: .genericContentBlockingBehaviors) else {
            return
          }
          
          try await self.compileContentBlocker(data: data)
        }
      } catch {
        log.error(error)
      }
    }
  }
  
  @MainActor private func set(genericEngine: AdblockEngine) {
    assertIsMainThread("Not on main thread")
    AdBlockStats.shared.set(genericEngine: genericEngine)
  }

  private func compileContentBlocker(data: Data) async throws {
    let blockList = BlocklistName.ad
    return try await blockList.compile(data: data)
  }
  
  private func loadEngineFromResourceDownloader(data: Data) async -> AdblockEngine {
    return await withCheckedContinuation({ continuation in
      self.serialQueue.async {
        let engine = AdblockEngine()
        
        if engine.deserialize(data: data) {
          continuation.resume(returning: engine)
        } else {
          log.error("Failed to deserialize data")
          continuation.resume(returning: engine)
        }
      }
    })
  }
}
