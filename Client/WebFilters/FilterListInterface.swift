// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Data

protocol FilterListInterface {
  @MainActor var uuid: String { get }
  @MainActor var filterListComponentId: String? { get }
}
 
extension FilterListInterface {
  @MainActor var resources: [ResourceDownloader.Resource] {
    guard let filterListComponentId = self.filterListComponentId else { return [] }
    
    return [
      .filterListContentBlockingBehaviors(uuid: uuid, componentId: filterListComponentId)
    ]
  }
}

extension FilterListSetting: FilterListInterface {
  @MainActor var filterListComponentId: String? { return componentId }
}

extension FilterList: FilterListInterface {
  @MainActor var filterListComponentId: String? { return componentId }
}
