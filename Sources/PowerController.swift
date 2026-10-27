import AppKit
import Combine

@MainActor final class PowerController: ObservableObject {
  @Published var active = false
  @Published var externalDisabled = false
  @Published var helperReady = false
  @Published var busy = false
  @Published var setupPending = false
  @Published var duration = 1800
  @Published var remaining = ""
  @Published var message = ""
  @Published var feedback = ""
  @Published var shortcutAvailable = true
  @Published var useSpeakers = UserDefaults.standard.object(forKey: "useSpeakers") as? Bool ?? true
  {
    didSet {
      UserDefaults.standard.set(useSpeakers, forKey: "useSpeakers")
      reminder.speakersOnly = useSpeakers
    }
  }
  @Published var vibration = VibrationPattern.load() {
    didSet {
      vibration.save()
      reminder.pattern = vibration
    }
  }
  let client = HelperClient()
  let reminder = Reminder()
  private var timer: Timer?
  private var refreshing = false
  private var wasClosed = false
  private var ticks = 0
  var onStopped: (() -> Void)?

  init(preview: Bool = false) {
    reminder.speakersOnly = useSpeakers
    reminder.pattern = vibration
    reminder.resultHandler = { [weak self] message in self?.feedback = message }
    guard !preview else { return }
    externalDisabled = PowerSensors.sleepDisabled == true
    timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    refresh()
  }
  var status: String {
    if busy { return "Preparing setup…" }
    if setupPending { return "Finish setup in Installer" }
    if active { return remaining.isEmpty ? "Awake until stopped" : "Awake · " + remaining }
    if externalDisabled { return "Sleep disabled outside Lidlight" }
    return helperReady ? "Normal sleep" : "One-time setup needed"
  }
  var action: String {
    if setupPending { return "Open Installer…" }
    if !helperReady { return HelperInstaller.installed ? "Update helper…" : "Enable Lidlight…" }
    return externalDisabled ? "Restore sleep" : "Keep awake"
  }
  func toggle() {
    guard !busy else { return }
    feedback = ""
    if setupPending {
      HelperInstaller.reopenSetup()
      return
    }
    guard helperReady else {
      install()
      return
    }
    perform(active ? "stop" : externalDisabled ? "restore" : "start")
  }
  func install() {
    guard !busy else { return }
    busy = true
    feedback = "Opening macOS Installer for one-time setup…"
    HelperInstaller.install { [weak self] error in
      guard let self else { return }
      self.busy = false
      self.setupPending = error == nil
      self.feedback = error ?? "Finish in Installer. Use Touch ID when offered."
      self.client.disconnect()
      self.refresh()
    }
  }
  func removeHelper() {
    guard !busy else { return }
    busy = true
    HelperInstaller.uninstall { [weak self] error in
      guard let self else { return }
      self.busy = false
      self.feedback = error ?? "Helper removed."
      self.client.disconnect()
      self.refresh()
    }
  }
  func stopForQuit(_ completion: @escaping () -> Void) {
    guard !busy else {
      feedback = "Finish or cancel setup before quitting."
      return
    }
    guard active else {
      completion()
      return
    }
    onStopped = completion
    perform("stop")
  }
  func testSound() { feedback = reminder.playSound() }
  func testHaptic() { feedback = reminder.playHaptic() }
  func previewPattern(_ pattern: VibrationPattern) {
    guard pattern.error == nil else { return }
    let saved = reminder.pattern
    reminder.pattern = pattern
    feedback = reminder.playHaptic()
    reminder.pattern = saved
  }

  private func apply(_ status: HelperStatus?) {
    guard let status else {
      helperReady = false
      active = false
      externalDisabled = PowerSensors.sleepDisabled == true
      message =
        HelperInstaller.installed
        ? "Update helper for this app build." : "Approve helper setup once to control sleep."
      return
    }
    helperReady = status.version == 2
    if setupPending && helperReady && HelperInstaller.isCurrentInstall {
      setupPending = false
      feedback = "Setup complete. No password needed for toggles."
    }
    active = status.active
    externalDisabled = status.disabled == true && !status.active
    if let seconds = status.remaining {
      remaining = String(format: "%d:%02d", seconds / 60, seconds % 60)
    } else {
      remaining = ""
    }
    message = status.message
    if !active {
      onStopped?()
      onStopped = nil
    }
  }
  private func perform(_ command: String) {
    busy = true
    client.request(command, duration: duration) { [weak self] status in
      guard let self else { return }
      self.busy = false
      self.apply(status)
      self.feedback = status?.message ?? "Helper unavailable. Choose Update helper."
    }
  }
  private func refresh() {
    guard !refreshing, !busy else { return }
    guard HelperInstaller.installed else {
      apply(nil)
      return
    }
    refreshing = true
    client.request("ping") { [weak self] status in
      self?.refreshing = false
      self?.apply(status)
    }
  }
  private func tick() {
    let closed = PowerSensors.lidClosed == true
    if active && closed && !wasClosed {
      reminder.warn()
      feedback = "Lid closed. Restoring sleep in 4 seconds."
    }
    wasClosed = closed
    ticks += 1
    if ticks % 5 == 0 { refresh() }
    if active && !busy && [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) {
      perform("stop")
      feedback = "Mac is running hot. Restoring sleep."
    }
  }
}
