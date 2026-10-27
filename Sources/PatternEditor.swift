import AppKit
import SwiftUI

struct PatternEditor: View {
  @ObservedObject var power: PowerController
  @State private var draft: VibrationPattern
  @State private var selectedPreset: VibrationPreset
  let close: () -> Void

  init(power: PowerController, initial: VibrationPattern? = nil, close: @escaping () -> Void) {
    self.power = power
    self.close = close
    _draft = State(initialValue: initial ?? power.vibration)
    _selectedPreset = State(initialValue: (initial ?? power.vibration).preset)
  }
  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          Picker(
            "Pattern",
            selection: Binding(
              get: { selectedPreset },
              set: { preset in
                selectedPreset = preset
                if preset != .custom {
                  let strength = draft.strength
                  draft = VibrationPattern.make(preset)
                  draft.strength = strength
                }
              })
          ) {
            ForEach(VibrationPreset.allCases) { preset in Text(preset.title).tag(preset) }
          }
          TextField("Tap groups", text: $draft.groupsText, prompt: Text("3, 3, 4"))
            .help(
              "Use commas to separate groups. For example, 2, 2, 3 plays two taps, two taps, then three taps."
            )
          Picker("Strength", selection: $draft.strength) {
            ForEach(VibrationStrength.allCases) { strength in Text(strength.title).tag(strength) }
          }.pickerStyle(.segmented)
        }
        Section {
          LabeledContent("Between taps") {
            Slider(value: $draft.interval, in: 0.06...0.30)
            Text(String(format: "%.2fs", draft.interval)).monospacedDigit().frame(
              width: 44, alignment: .trailing)
          }
          LabeledContent("Between groups") {
            Slider(value: $draft.pause, in: 0.08...0.60)
            Text(String(format: "%.2fs", draft.pause)).monospacedDigit().frame(
              width: 44, alignment: .trailing)
          }
        }
        Section {
          VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 12) {
                ForEach(Array((draft.groups ?? []).enumerated()), id: \.offset) { _, count in
                  HStack(spacing: 4) {
                    ForEach(0..<count, id: \.self) { _ in
                      Circle().fill(.primary).frame(width: 5, height: 5)
                    }
                  }
                }
              }.frame(height: 16)
            }.accessibilityLabel("Tap groups: " + draft.rhythm)
            Text(draft.error ?? draft.summary).font(.caption).foregroundStyle(
              draft.error == nil ? Color.secondary : Color.red)
            Text("Patterns finish before normal sleep returns after four seconds.")
              .font(.caption).foregroundStyle(.secondary)
          }.padding(.vertical, 2)
        }
      }
      .formStyle(.grouped)
      .onChange(of: draft) { _, value in selectedPreset = value.preset }
      Divider()
      HStack {
        Button("Preview") { power.previewPattern(draft) }.disabled(draft.error != nil)
        Text(power.feedback).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(
          maxWidth: .infinity, alignment: .leading)
        Button("Cancel", action: close).keyboardShortcut(.cancelAction)
        Button("Save") {
          power.vibration = draft
          close()
        }
        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(
          draft.error != nil)
      }.controlSize(.small).buttonStyle(.bordered).padding(14)
    }
    .frame(width: 460, height: 390)
    .background(Color(nsColor: .windowBackgroundColor))
    .tint(Brand.accent)
  }
}

@MainActor final class PatternWindow: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  func windowWillClose(_ notification: Notification) { window = nil }
  func show(power: PowerController) {
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 390), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    window.delegate = self
    window.title = "PeachPocket · Vibration pattern"
    window.isReleasedWhenClosed = false
    window.contentViewController = NSHostingController(
      rootView: PatternEditor(
        power: power,
        close: { [weak self] in
          self?.window?.close()
          self?.window = nil
        }))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    self.window = window
  }
}
