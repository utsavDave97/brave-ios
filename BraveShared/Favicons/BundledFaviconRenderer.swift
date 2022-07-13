// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import UIKit
import BraveCore
import Shared

private let log = Logger.browserLogger

/// A class for rendering a Bundled FavIcon onto a `UIImage`
class BundledFaviconImageRenderer {
  private var task: DispatchWorkItem?
  
  /// Folder where custom favicons are stored.
  static let faviconOverridesDirectory = "favorite_overrides"
  /// For each favicon override, there should be a file that contains info of what background color to use.
  static let faviconOverridesBackgroundSuffix = ".background_color"

  deinit {
    task?.cancel()
  }
  
  func loadIcon(url: URL, completion: ((Favicon?) -> Void)?) {
    let taskCompletion = { [weak self] (image: Favicon?) in
      self?.task = nil
      
      DispatchQueue.main.async {
        completion?(image)
      }
    }
    
    task?.cancel()
    task = DispatchWorkItem { [weak self] in
      guard let self = self, !self.isCancelled else {
        taskCompletion(nil)
        return
      }
      
      if let icon = self.customIcon(for: url) ?? self.bundledIcon(for: url) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
          guard let self = self, !self.isCancelled else {
            taskCompletion(nil)
            return
          }
        
          // Render the Favicon on a UIImage
          UIImage.renderImage(icon.image, backgroundColor: icon.backgroundColor) { [weak self] favicon in
            guard let self = self, !self.isCancelled else {
              taskCompletion(nil)
              return
            }
            
            taskCompletion(favicon)
          }
        }
      } else {
        // No need to render a monogram
        taskCompletion(nil)
      }
    }
    
    if let task = task {
      DispatchQueue.main.async(execute: task)
    }
  }
  
  private var isCancelled: Bool {
    guard let cancellable = task else {
      return true
    }
    
    return cancellable.isCancelled
  }
  
  /// Icon attributes for any custom icon overrides
  ///
  /// If the app does not contain a custom icon for the site provided `nil`
  /// will be returned
  private func customIcon(for url: URL) -> (image: UIImage, backgroundColor: UIColor)? {
    guard let folder = FileManager.default.getOrCreateFolder(name: BundledFaviconImageRenderer.faviconOverridesDirectory) else {
      return nil
    }
    
    let fileName = url.absoluteString.toBase64()
    let backgroundName = fileName + BundledFaviconImageRenderer.faviconOverridesBackgroundSuffix
    let backgroundPath = folder.appendingPathComponent(backgroundName)
    do {
      let colorString = try String(contentsOf: backgroundPath)
      let colorFromHex = UIColor(colorString: colorString)

      if FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path) {
        let imagePath = folder.appendingPathComponent(fileName)
        if let image = UIImage(contentsOfFile: imagePath.path) {
          return (image, colorFromHex)
        }
        return nil
      }
    } catch {
      return nil
    }
    return nil
  }

  // MARK: - Bundled Icons

  /// Icon attributes for icons that are bundled in the app by default.
  ///
  /// If the app does not contain the icon for the site provided `nil` will be
  /// returned
  private func bundledIcon(for url: URL) -> (image: UIImage, backgroundColor: UIColor)? {
    // Problem: Sites like amazon exist with .ca/.de and many other tlds.
    // Solution: They are stored in the default icons list as "amazon" instead of "amazon.com" this allows us to have favicons for every tld."
    // Here, If the site is in the multiRegionDomain array look it up via its second level domain (amazon) instead of its baseDomain (amazon.com)
    let hostName = url.hostSLD
    var bundleIcon: (color: UIColor, url: String)?
    if Self.multiRegionDomains.contains(hostName), let icon = Self.bundledIcons[hostName] {
      bundleIcon = icon
    } else if let name = url.baseDomain, let icon = Self.bundledIcons[name] {
      bundleIcon = icon
    }
    guard let icon = bundleIcon, let image = UIImage(contentsOfFile: icon.url) else {
      return nil
    }

    return (
      image.createScaled(CGSize(width: 40.0, height: 40.0)),
      icon.color
    )
  }
  
  private static let multiRegionDomains = ["craigslist", "google", "amazon"]
  
  private static let bundledIcons: [String: (color: UIColor, url: String)] = {
    guard let filePath = Bundle.current.path(forResource: "top_sites", ofType: "json") else {
      log.error("Failed to get bundle path for \"top_sites.json\"")
      return [:]
    }
    do {
      let file = try Data(contentsOf: URL(fileURLWithPath: filePath))
      let json = try JSONDecoder().decode([TopSite].self, from: file)
      var icons: [String: (color: UIColor, url: String)] = [:]
      
      json.forEach({
        guard let url = $0.domain,
              let color = $0.backgroundColor?.lowercased(),
              let path = $0.imageURL?.replacingOccurrences(of: ".png", with: "")
        else {
          return
        }
        
        let filePath = Bundle.current.path(forResource: "TopSites/" + path, ofType: "png")
        if let filePath = filePath {
          if color == "#fff" {
            icons[url] = (.white, filePath)
          } else {
            icons[url] = (UIColor(colorString: color.replacingOccurrences(of: "#", with: "")), filePath)
          }
        }
      })
      return icons
    } catch {
      log.error("Failed to get default icons at \(filePath): \(error.localizedDescription)")
      return [:]
    }
  }()
  
  private struct TopSite: Codable {
    let domain: String?
    let backgroundColor: String?
    let imageURL: String?
    
    private enum CodingKeys: String, CodingKey {
      case domain
      case backgroundColor = "background_color"
      case imageURL = "image_url"
    }
  }
}
