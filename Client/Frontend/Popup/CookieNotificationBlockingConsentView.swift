// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import SwiftUI
import Strings
import DesignSystem
import BraveShared

struct CookieNotificationBlockingConsentView: View {
  public static let contentHeight = 480.0
  public static let contentWidth = 344.0
  private static let gifHeight = 328.0
  private static let bottomSectionHeight = contentHeight - gifHeight
  
  private let animation = Animation.easeOut(duration: 0.5).delay(0)
  private let transition = AnyTransition.scale(scale: 1.1).combined(with: .opacity)
  private let textPadding: CGFloat = 16
  
  @Environment(\.presentationMode) var presentationMode
  @State private var showAnimation = false
  
  private var yesButton: some View {
    Button(Strings.yesBlockCookieConsentNotices) {
      withAnimation(animation) {
        self.showAnimation = true
      }

      if !FilterListResourceDownloader.shared.enableFilterList(for: FilterList.cookieConsentNoticesComponentID, isEnabled: true) {
        assertionFailure("This filter list should exist or this UI is completely useless")
      }
      
      Task { @MainActor in
        try await Task.sleep(seconds: 3.5)
        self.presentationMode.wrappedValue.dismiss()
      }
    }
    .buttonStyle(BraveFilledButtonStyle(size: .large))
    .multilineTextAlignment(.center)
    .transition(transition)
  }
  
  private var noButton: some View {
    Button(Strings.noThanks) {
      self.presentationMode.wrappedValue.dismiss()
    }
    .font(Font.body.weight(.semibold))
    .foregroundColor(.accentColor)
    .multilineTextAlignment(.center)
    .transition(transition)
  }
  
  var body: some View {
    ScrollView {
      VStack {
        VStack {
          if !showAnimation {
            VStack(alignment: .center, spacing: textPadding) {
              Text(Strings.blockCookieConsentNoticesPopupTitle)
                .font(.title)
                .foregroundColor(Color(UIColor.braveLabel))
                .multilineTextAlignment(.center)
              
              Text(Strings.blockCookieConsentNoticesPopupDescription)
                .font(.body)
                .foregroundColor(Color(UIColor.braveLabel))
                .multilineTextAlignment(.center)
            }
            .transition(transition)
            .padding(textPadding)
            .padding(.top, 80)
          }
        }
        .frame(width: Self.contentWidth, alignment: .center)
        .frame(minHeight: Self.gifHeight)
        .background(
          GIFImage(asset: "cookie-consent-animation", animate: showAnimation)
            .frame(width: Self.contentWidth, height: Self.gifHeight, alignment: .top),
          alignment: .top
        )
        
        VStack(alignment: .center, spacing: textPadding) {
          if !showAnimation {
            yesButton
            noButton
          }
        }
        .padding(textPadding)
      }
    }
    .frame(width: Self.contentWidth, height: Self.contentHeight, alignment: .center)
    .background(
      Image("cookie-consent-background", bundle: .current),
      alignment: .bottomLeading
    )
    .background(Color(UIColor.braveBackground))
  }
}

#if DEBUG
struct CookieNotificationBlockingConsentView_Previews: PreviewProvider {
  static var previews: some View {
    CookieNotificationBlockingConsentView()
  }
}
#endif
