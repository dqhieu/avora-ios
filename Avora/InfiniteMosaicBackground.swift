//
//  InfiniteMosaicBackground.swift
//  Avora
//
//  Created by Hieu Dinh on 7/4/26.
//

import SwiftUI

struct InfiniteMosaicBackground: View {
  let imageName: String = "LoginBackground"
  let imageSize = CGSize(width: 1080, height: 3840)
  let speed: CGFloat = 24 // points per second

  @State private var startDate = Date()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      TimelineView(.animation) { timeline in
        let tileWidth = proxy.size.width
        let tileHeight = tileWidth * imageSize.height / imageSize.width
        let elapsed = timeline.date.timeIntervalSince(startDate)
        let scroll = reduceMotion ? 0 : CGFloat(elapsed) * speed
        let yOffset = -scroll.truncatingRemainder(dividingBy: tileHeight)
        let copies = max(2, Int(ceil(proxy.size.height / tileHeight)) + 2)

        ZStack(alignment: .top) {
          ForEach(0..<copies, id: \.self) { index in
            Image(imageName)
              .resizable()
              .scaledToFill()
              .frame(width: tileWidth, height: tileHeight)
              .clipped()
              .offset(y: yOffset + CGFloat(index) * tileHeight)
          }
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        .clipped()
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
