import AppKit
import SwiftUI

enum Brand {
  static let accent = Color(red: 0.72, green: 0.30, blue: 0.20)
}

@MainActor enum MarkImage {
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
    Image(nsImage: MarkImage.source(active: active)).resizable().renderingMode(.template)
      .scaledToFit()
  }
}

private struct Peach: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 260, y: 40))
    p.addCurve(
      to: CGPoint(x: 15, y: 185), control1: CGPoint(x: 140, y: -45),
      control2: CGPoint(x: -10, y: 25))
    p.addCurve(
      to: CGPoint(x: 260, y: 455), control1: CGPoint(x: 30, y: 335),
      control2: CGPoint(x: 180, y: 455))
    p.addCurve(
      to: CGPoint(x: 505, y: 185), control1: CGPoint(x: 340, y: 455),
      control2: CGPoint(x: 490, y: 335))
    p.addCurve(
      to: CGPoint(x: 260, y: 40), control1: CGPoint(x: 530, y: 25),
      control2: CGPoint(x: 380, y: -45))
    p.closeSubpath()
    return p.applying(CGAffineTransform(scaleX: rect.width / 520, y: rect.height / 460))
  }
}

private struct Pocket: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 35, y: 0))
    p.addLine(to: CGPoint(x: 565, y: 0))
    p.addQuadCurve(to: CGPoint(x: 600, y: 35), control: CGPoint(x: 600, y: 0))
    p.addLine(to: CGPoint(x: 600, y: 205))
    p.addCurve(
      to: CGPoint(x: 300, y: 410), control1: CGPoint(x: 600, y: 300),
      control2: CGPoint(x: 430, y: 370))
    p.addCurve(
      to: CGPoint(x: 0, y: 205), control1: CGPoint(x: 170, y: 370), control2: CGPoint(x: 0, y: 300))
    p.addLine(to: CGPoint(x: 0, y: 35))
    p.addQuadCurve(to: CGPoint(x: 35, y: 0), control: .zero)
    p.closeSubpath()
    return p.applying(CGAffineTransform(scaleX: rect.width / 600, y: rect.height / 410))
  }
}

private struct Leaf: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 0, y: 110))
    p.addCurve(
      to: CGPoint(x: 210, y: 5), control1: CGPoint(x: 5, y: 10), control2: CGPoint(x: 125, y: -30))
    p.addCurve(
      to: CGPoint(x: 0, y: 110), control1: CGPoint(x: 180, y: 110), control2: CGPoint(x: 75, y: 145)
    )
    p.closeSubpath()
    return p.applying(CGAffineTransform(scaleX: rect.width / 210, y: rect.height / 140))
  }
}

private struct PeachCrease: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: rect.midX, y: 0))
    p.addCurve(
      to: CGPoint(x: rect.midX + 10, y: rect.maxY),
      control1: CGPoint(x: rect.midX - 32, y: rect.height * 0.28),
      control2: CGPoint(x: rect.midX + 30, y: rect.height * 0.62))
    return p
  }
}

struct AppIconView: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 218)
        .fill(
          LinearGradient(
            colors: [
              Color(red: 1, green: 0.97, blue: 0.91), Color(red: 0.92, green: 0.89, blue: 0.84),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
      RoundedRectangle(cornerRadius: 216)
        .stroke(
          LinearGradient(
            colors: [.white, Color(red: 0.79, green: 0.76, blue: 0.71)], startPoint: .top,
            endPoint: .bottom), lineWidth: 3
        ).padding(2)
      Ellipse().fill(Color(red: 0.25, green: 0.25, blue: 0.29).opacity(0.18))
        .frame(width: 600, height: 90).blur(radius: 30).position(x: 512, y: 844)
      Peach()
        .fill(
          LinearGradient(
            stops: [
              .init(color: Color(red: 1, green: 0.83, blue: 0.55), location: 0),
              .init(color: Color(red: 1, green: 0.65, blue: 0.46), location: 0.48),
              .init(color: Color(red: 0.94, green: 0.38, blue: 0.38), location: 1),
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .frame(width: 530, height: 460).shadow(
          color: Color(red: 0.65, green: 0.29, blue: 0.20).opacity(0.18), radius: 12, y: 10
        ).position(x: 512, y: 418)
      PeachCrease().stroke(
        Color(red: 0.76, green: 0.29, blue: 0.22).opacity(0.24),
        style: StrokeStyle(lineWidth: 5, lineCap: .round)
      )
      .frame(width: 90, height: 270).position(x: 512, y: 367)
      Leaf().fill(
        LinearGradient(
          colors: [
            Color(red: 0.57, green: 0.68, blue: 0.40), Color(red: 0.28, green: 0.45, blue: 0.31),
          ], startPoint: .topLeading, endPoint: .bottomTrailing)
      )
      .frame(width: 220, height: 140).rotationEffect(.degrees(-13)).shadow(
        color: .black.opacity(0.10), radius: 5, y: 5
      ).position(x: 601, y: 207)
      Pocket().fill(
        LinearGradient(
          colors: [
            Color(red: 0.30, green: 0.40, blue: 0.52), Color(red: 0.14, green: 0.21, blue: 0.32),
          ], startPoint: .topLeading, endPoint: .bottomTrailing)
      )
      .frame(width: 600, height: 410).shadow(
        color: Color(red: 0.15, green: 0.20, blue: 0.29).opacity(0.20), radius: 12, y: 12
      ).position(x: 512, y: 649)
      Pocket().stroke(
        LinearGradient(
          colors: [.white.opacity(0.30), .black.opacity(0.10)], startPoint: .top, endPoint: .bottom),
        lineWidth: 3
      )
      .frame(width: 598, height: 408).position(x: 512, y: 648)
      Pocket().stroke(
        Color(red: 0.80, green: 0.83, blue: 0.84).opacity(0.80),
        style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 8])
      )
      .frame(width: 545, height: 350).position(x: 512, y: 651)
      Capsule().fill(.white.opacity(0.12)).frame(width: 525, height: 4).position(x: 512, y: 470)
    }
    .frame(width: 1024, height: 1024)
    .padding(55)
    .frame(width: 1134, height: 1134)
  }
}
