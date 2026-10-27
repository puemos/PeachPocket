import AppKit
import SwiftUI

enum Brand {
  static let accent = Color(red: 0.72, green: 0.30, blue: 0.20)
}

@MainActor enum MarkImage {
  static let artwork: NSImage? = {
    guard let url = Bundle.main.url(forResource: "peachpocket-pixel", withExtension: "png") else {
      return nil
    }
    return NSImage(contentsOf: url)
  }()
  static func source(active: Bool) -> NSImage {
    let name = active ? "peachpocket-awake" : "peachpocket-rest"
    guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
      let image = NSImage(contentsOf: url)
    else {
      return NSImage(systemSymbolName: "leaf", accessibilityDescription: "PeachPocket") ?? NSImage()
    }
    image.isTemplate = true
    return image
  }
  static func menu(active: Bool) -> NSImage {
    let image = source(active: active)
    image.size = NSSize(width: 18, height: 18)
    image.accessibilityDescription = "PeachPocket"
    return image
  }
}

struct MarkView: View {
  var active: Bool
  var body: some View {
    if let image = MarkImage.artwork {
      Image(nsImage: image).resizable().renderingMode(.original).interpolation(.high).scaledToFit()
        .accessibilityLabel("PeachPocket")
    } else {
      Image(nsImage: MarkImage.source(active: active)).resizable().renderingMode(.template)
        .scaledToFit()
    }
  }
}
