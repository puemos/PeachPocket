import AppKit
import CoreAudio

@MainActor final class Reminder {
  private var sound: NSSound?
  private var hapticTask: Process?
  var resultHandler: ((String) -> Void)?
  var speakersOnly = true
  var pattern = VibrationPattern()

  static func builtInOutput() -> (id: AudioDeviceID, uid: String)? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
    else { return nil }
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr
    else { return nil }
    for device in devices {
      var transport: UInt32 = 0
      size = UInt32(MemoryLayout<UInt32>.size)
      address.mSelector = kAudioDevicePropertyTransportType
      guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr,
        transport == kAudioDeviceTransportTypeBuiltIn
      else { continue }
      address.mSelector = kAudioDevicePropertyStreams
      address.mScope = kAudioDevicePropertyScopeOutput
      guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0
      else { continue }
      var uid: Unmanaged<CFString>?
      size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
      address.mSelector = kAudioDevicePropertyDeviceUID
      address.mScope = kAudioObjectPropertyScopeGlobal
      guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else {
        continue
      }
      if let uid { return (device, uid.takeRetainedValue() as String) }
    }
    return nil
  }

  static func isMuted(_ device: AudioDeviceID) -> Bool {
    var muted: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain)
    if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr, muted != 0 {
      return true
    }
    var volume: Float32 = 1
    address.mSelector = kAudioDevicePropertyVolumeScalar
    size = UInt32(MemoryLayout<Float32>.size)
    return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr
      && volume < 0.01
  }

  func playSound() -> String {
    sound?.stop()
    guard
      let sound = NSSound(
        contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"), byReference: false)
    else { return "Could not load the alert sound." }
    self.sound = sound
    sound.volume = 1
    let speaker = speakersOnly ? Self.builtInOutput() : nil
    if speakersOnly && speaker == nil {
      return "Mac speakers unavailable. Select current audio output in the menu."
    }
    if let speaker { sound.playbackDeviceIdentifier = speaker.uid }
    if let speaker, Self.isMuted(speaker.id) {
      return "Mac speakers are muted. Raise their volume, then test again."
    }
    guard sound.play() else { return "Audio playback failed. Check Sound settings." }
    return speaker == nil ? "Sound started on current output." : "Sound started on Mac speakers."
  }

  func playHaptic() -> String {
    if let error = pattern.error { return error }
    guard hapticTask == nil else { return "Trackpad vibration is already running." }
    guard let binary = Bundle.main.url(forResource: "LidlightHaptic", withExtension: nil) else {
      return "Vibration tool missing. Rebuild Lidlight."
    }
    let task = Process()
    let output = Pipe()
    task.executableURL = binary
    task.arguments = [pattern.argument]
    task.standardOutput = output
    task.standardError = FileHandle.nullDevice
    task.terminationHandler = { [weak self] task in
      let message = String(
        decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      Task { @MainActor in
        self?.hapticTask = nil
        self?.resultHandler?(
          message.isEmpty ? "Trackpad vibration unavailable on this macOS." : message)
      }
    }
    hapticTask = task
    do {
      try task.run()
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if task.isRunning { task.terminate() } }
      return "Playing " + pattern.rhythm + "…"
    } catch {
      hapticTask = nil
      return "Could not start vibration: " + error.localizedDescription
    }
  }

  func warn() {
    _ = playSound()
    _ = playHaptic()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in _ = self?.playSound() }
  }
}
