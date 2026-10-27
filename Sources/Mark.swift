import AppKit
import SwiftUI

@MainActor enum MarkImage {
  static func source(active: Bool) -> NSImage {
    let name = active ? "cup-awake" : "cup-rest"
    guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
      let image = NSImage(contentsOf: url)
    else {
      return NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "Lidlight")
        ?? NSImage()
    }
    image.isTemplate = true
    return image
  }
  static func menu(active: Bool) -> NSImage {
    let image = source(active: active)
    image.size = NSSize(width: 18, height: 18)
    image.accessibilityDescription = "Lidlight"
    return image
  }
}

struct MarkView: View {
  var active: Bool
  var body: some View {
    Image(nsImage: MarkImage.source(active: active)).resizable().renderingMode(.template)
      .scaledToFit()
  }
}

private struct PorcelainCup: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 0, y: 0))
    p.addLine(to: CGPoint(x: 440, y: 0))
    p.addLine(to: CGPoint(x: 410, y: 230))
    p.addCurve(
      to: CGPoint(x: 220, y: 315), control1: CGPoint(x: 400, y: 300),
      control2: CGPoint(x: 315, y: 315))
    p.addCurve(
      to: CGPoint(x: 30, y: 230), control1: CGPoint(x: 125, y: 315),
      control2: CGPoint(x: 40, y: 300))
    p.closeSubpath()
    return p.applying(CGAffineTransform(scaleX: rect.width / 440, y: rect.height / 315))
  }
}

private struct Steam: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: rect.midX + rect.width * 0.15, y: rect.maxY))
    p.addCurve(
      to: CGPoint(x: rect.midX - rect.width * 0.15, y: rect.minY),
      control1: CGPoint(x: rect.minX - rect.width * 0.3, y: rect.height * 0.62),
      control2: CGPoint(x: rect.maxX + rect.width * 0.3, y: rect.height * 0.38))
    return p
  }
}

struct AppIconView: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 218)
        .fill(
          RadialGradient(
            colors: [Color(white: 0.29), Color(white: 0.105)], center: .topLeading, startRadius: 0,
            endRadius: 1200))
      RoundedRectangle(cornerRadius: 216)
        .stroke(
          LinearGradient(
            colors: [Color(white: 0.48), Color(white: 0.08)], startPoint: .top, endPoint: .bottom),
          lineWidth: 3
        ).padding(2)
      Ellipse().fill(.black.opacity(0.42)).frame(width: 570, height: 100).blur(radius: 28).position(
        x: 508, y: 775)
      Ellipse().fill(
        LinearGradient(
          colors: [Color(white: 0.84), Color(white: 0.60)], startPoint: .top, endPoint: .bottom)
      )
      .frame(width: 570, height: 104).position(x: 500, y: 742)
      Ellipse().stroke(.white.opacity(0.70), lineWidth: 5).frame(width: 556, height: 90).position(
        x: 500, y: 736)
      Ellipse().stroke(.black.opacity(0.10), lineWidth: 4).frame(width: 408, height: 53).position(
        x: 500, y: 734)
      Ellipse().stroke(
        LinearGradient(
          colors: [Color(white: 0.98), Color(white: 0.56)], startPoint: .topLeading,
          endPoint: .bottomTrailing), lineWidth: 58
      )
      .frame(width: 176, height: 185).shadow(color: .black.opacity(0.20), radius: 12, y: 12)
      .position(x: 729, y: 523)
      PorcelainCup().fill(
        LinearGradient(
          stops: [
            .init(color: Color(white: 0.86), location: 0),
            .init(color: Color(white: 0.99), location: 0.24),
            .init(color: Color(white: 0.93), location: 0.57),
            .init(color: Color(white: 0.66), location: 1),
          ], startPoint: .leading, endPoint: .trailing)
      )
      .frame(width: 440, height: 315).shadow(color: .black.opacity(0.17), radius: 12, y: 12)
      .position(x: 475, y: 557.5)
      Ellipse().fill(
        LinearGradient(colors: [.white, Color(white: 0.80)], startPoint: .top, endPoint: .bottom)
      ).frame(width: 440, height: 126).position(x: 475, y: 400)
      Ellipse().fill(
        LinearGradient(
          colors: [Color(white: 0.30), Color(white: 0.075)], startPoint: .top, endPoint: .bottom)
      ).frame(width: 397, height: 91).position(x: 475, y: 400)
      Ellipse().trim(from: 0.52, to: 0.91).stroke(.white.opacity(0.25), lineWidth: 3).frame(
        width: 378, height: 75
      ).position(x: 475, y: 401)
      Steam().stroke(
        LinearGradient(
          colors: [.white.opacity(0.05), .white.opacity(0.65)], startPoint: .top, endPoint: .bottom),
        style: StrokeStyle(lineWidth: 17, lineCap: .round)
      )
      .frame(width: 58, height: 132).blur(radius: 0.6).position(x: 422, y: 235)
      Steam().stroke(
        LinearGradient(
          colors: [.white.opacity(0.03), .white.opacity(0.52)], startPoint: .top, endPoint: .bottom),
        style: StrokeStyle(lineWidth: 17, lineCap: .round)
      )
      .frame(width: 58, height: 132).blur(radius: 0.6).position(x: 535, y: 235)
    }
    .frame(width: 1024, height: 1024)
    .padding(55)
    .frame(width: 1134, height: 1134)
  }
}
