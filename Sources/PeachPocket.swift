import AppKit
import Carbon
import Combine
import SwiftUI

struct PeachPocketView: View {
  @ObservedObject var power: PowerController
  var quit: () -> Void = {}
  var editPattern: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 9) {
        MarkView(active: power.active).foregroundStyle(.primary)
          .frame(width: 24, height: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text("PeachPocket").font(.system(size: 13, weight: .semibold))
          Text(power.status).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 4)
        if power.busy {
          ProgressView().controlSize(.small).frame(width: 30)
        } else if power.helperReady && !power.externalDisabled && !power.setupPending {
          Toggle("Keep awake", isOn: Binding(get: { power.active }, set: { _ in power.toggle() }))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
            .accessibilityLabel("Keep awake")
        }
      }

      if !power.helperReady || power.externalDisabled || power.setupPending {
        Button(power.action, action: power.toggle)
          .buttonStyle(.borderedProminent).controlSize(.small).frame(maxWidth: .infinity)
          .disabled(power.busy)
      } else {
        Picker("Duration", selection: $power.duration) {
          Text("30 min").tag(1800)
          Text("1 hour").tag(3600)
          Text("Until stopped").tag(0)
        }
        .pickerStyle(.segmented).labelsHidden().controlSize(.small)
        .disabled(power.active || power.busy)
      }

      Divider()
      HStack {
        Image(systemName: "laptopcomputer").foregroundStyle(.secondary)
        Text("Lid closed").font(.system(size: 11))
        Spacer()
        Text("Sleep after 4s").font(.system(size: 11)).foregroundStyle(.secondary)
      }
      HStack(spacing: 8) {
        Button(action: power.testSound) {
          Label("Sound", systemImage: "speaker.wave.2").frame(maxWidth: .infinity)
        }
        Button(action: power.testHaptic) {
          Label("Vibration", systemImage: "waveform").frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.bordered).controlSize(.small)
      Text(power.feedback.isEmpty ? power.vibration.reminderLabel : power.feedback)
        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .topLeading)
        .help(power.feedback.isEmpty ? power.message : power.feedback)
        .accessibilityLabel(power.feedback.isEmpty ? power.vibration.reminderLabel : power.feedback)
      Divider()
      HStack {
        Text(power.shortcutAvailable ? "⌃⌥⌘K" : "Shortcut unavailable")
          .font(.system(size: 10)).foregroundStyle(.secondary)
        Spacer()
        Menu {
          Button("Vibration pattern…", action: editPattern)
          Divider()
          Toggle("Use Mac speakers for alerts", isOn: $power.useSpeakers)
          Divider()
          Button("Update helper…", action: power.install).disabled(power.busy || power.active)
          Button("Remove helper…", action: power.removeHelper).disabled(power.busy || power.active)
          Divider()
          Button("Quit PeachPocket", action: quit)
        } label: {
          Image(systemName: "gearshape").font(.system(size: 11))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("PeachPocket settings")
      }
    }
    .padding(12)
    .frame(width: 268, height: 212, alignment: .topLeading)
    .background(.regularMaterial)
    .tint(Brand.accent)
  }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  let preview = CommandLine.arguments.contains("--render-preview")
  lazy var power = PowerController(preview: preview)
  var status: NSStatusItem!
  let popover = NSPopover()
  let patternWindow = PatternWindow()
  var hotKey: EventHotKeyRef?
  var handler: EventHandlerRef?
  var subscription: AnyCancellable?

  func applicationDidFinishLaunching(_ notification: Notification) {
    if preview {
      renderPreview()
      return
    }
    if CommandLine.arguments.contains("--export-icon") {
      exportIcon()
      return
    }
    if CommandLine.arguments.contains("--installer-check") {
      let destination = URL(fileURLWithPath: CommandLine.arguments.last ?? "/tmp")
        .appendingPathComponent("installer-check.sh")
      HelperInstaller.install(scriptDestination: destination) { error in
        print(error ?? "Installer generated and signature read successfully")
        NSApp.terminate(nil)
      }
      return
    }
    if CommandLine.arguments.contains("--sound-check") {
      let reminder = Reminder()
      print(reminder.playSound())
      print(reminder.playHaptic())
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
        withExtendedLifetime(reminder) { NSApp.terminate(nil) }
      }
      return
    }
    guard
      NSRunningApplication.runningApplications(withBundleIdentifier: "local.lidlight.app").count
        <= 1
    else {
      NSApp.terminate(nil)
      return
    }
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    status.button?.image = MarkImage.menu(active: false)
    status.button?.target = self
    status.button?.action = #selector(showPopover)
    let host = NSHostingController(
      rootView: PeachPocketView(
        power: power, quit: { NSApp.terminate(nil) },
        editPattern: { [weak self] in
          guard let self else { return }
          self.popover.performClose(nil)
          self.patternWindow.show(power: self.power)
        }))
    host.view.frame = NSRect(x: 0, y: 0, width: 268, height: 212)
    host.preferredContentSize = NSSize(width: 268, height: 212)
    popover.contentViewController = host
    popover.contentSize = NSSize(width: 268, height: 212)
    popover.behavior = .transient
    popover.animates = true
    subscription = power.$active.combineLatest(power.$externalDisabled).removeDuplicates {
      $0.0 == $1.0 && $0.1 == $1.1
    }.sink { [weak self] active, external in
      self?.status.button?.image = MarkImage.menu(active: active || external)
      self?.status.button?.toolTip =
        active
        ? "PeachPocket · Awake · ⌃⌥⌘K"
        : external
          ? "PeachPocket · Sleep disabled outside app" : "PeachPocket · Normal sleep · ⌃⌥⌘K"
    }
    var event = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let installed = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, context in
        guard let context else { return OSStatus(eventNotHandledErr) }
        let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in delegate.power.toggle() }
        return noErr
      }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    let registered = RegisterEventHotKey(
      UInt32(kVK_ANSI_K), UInt32(controlKey | optionKey | cmdKey),
      EventHotKeyID(signature: 0x4C49_444C, id: 1), GetApplicationEventTarget(), 0, &hotKey)
    power.shortcutAvailable = installed == noErr && registered == noErr
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      if CommandLine.arguments.contains("--pattern-editor") {
        self.patternWindow.show(power: self.power)
      } else {
        self.showPopover()
      }
    }
  }
  @objc func showPopover() {
    guard let button = status.button else { return }
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      guard let self else { return }
      self.popover.contentSize = NSSize(width: 268, height: 212)
      self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      self.popover.contentViewController?.view.window?.makeKey()
      if CommandLine.arguments.contains("--ui-check") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.checkLiveUI() }
      }
    }
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if preview || CommandLine.arguments.contains("--export-icon")
      || CommandLine.arguments.contains("--sound-check")
      || CommandLine.arguments.contains("--installer-check")
    {
      return .terminateNow
    }
    if power.busy {
      power.feedback = "Finish or cancel setup before quitting."
      return .terminateCancel
    }
    if power.active {
      power.stopForQuit { NSApp.reply(toApplicationShouldTerminate: true) }
      return .terminateLater
    }
    power.client.disconnect()
    return .terminateNow
  }
  func checkLiveUI() {
    guard let view = popover.contentViewController?.view, let window = view.window,
      let screen = window.screen
    else {
      let report = "isShown=\(popover.isShown), args=\(CommandLine.arguments)"
      try? report.write(
        toFile: (CommandLine.arguments.last ?? "/tmp") + "/ui-check-error.txt", atomically: true,
        encoding: .utf8)
      return
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments.last ?? "/tmp")
    let report: [String: Any] = [
      "window": NSStringFromRect(window.frame),
      "screen": NSStringFromRect(screen.frame),
      "insideScreen": screen.frame.contains(window.frame),
      "contentWidth": view.bounds.width,
      "contentHeight": view.bounds.height,
      "helperReady": power.helperReady,
    ]
    if let json = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) {
      try? json.write(to: directory.appendingPathComponent("ui-check.json"))
    }
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
      view.cacheDisplay(in: view.bounds, to: bitmap)
      if let png = bitmap.representation(using: .png, properties: [:]) {
        try? png.write(to: directory.appendingPathComponent("preview-live.png"))
      }
    }
  }

  func renderPreview() {
    let directory = CommandLine.arguments.last ?? "/tmp"
    for mode in 0...3 {
      power.helperReady = mode != 0
      power.active = mode == 2
      power.externalDisabled = mode == 3
      power.remaining = "28:42"
      let name = ["setup", "rest", "awake", "restore"][mode]
      for dark in [false, true] {
        let view = PeachPocketView(power: power).environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 268, height: 212), styleMask: [.borderless],
          backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        host.display()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
          host.cacheDisplay(in: host.bounds, to: bitmap)
          if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(
              to: URL(fileURLWithPath: directory).appendingPathComponent(
                "preview-\(name)\(dark ? "-dark" : "").png"))
          }
        }
        window.orderOut(nil)
      }
    }
    for dark in [false, true] {
      let view = PatternEditor(power: power, initial: .make(.heartbeat), close: {}).environment(
        \.colorScheme, dark ? .dark : .light)
      let host = NSHostingView(rootView: view)
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 460, height: 390), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      window.contentView = host
      window.orderFront(nil)
      host.layoutSubtreeIfNeeded()
      host.display()
      if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
          try? data.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
              "preview-pattern\(dark ? "-dark" : "").png"))
        }
      }
      window.orderOut(nil)
    }
    NSApp.terminate(nil)
  }
  func exportIcon() {
    let directory = CommandLine.arguments.last ?? "/tmp"
    guard let source = Bundle.main.url(forResource: "peachpocket-pixel", withExtension: "png"),
      let data = try? Data(contentsOf: source)
    else {
      FileHandle.standardError.write(Data("Missing PeachPocket artwork.\n".utf8))
      exit(1)
    }
    do {
      try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("icon-master.png"))
    } catch {
      FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
      exit(1)
    }
    NSApp.terminate(nil)
  }
}

@main struct PeachPocketApp {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}
