import Foundation

enum VibrationPreset: String, CaseIterable, Identifiable {
  case knock, steady, heartbeat, custom
  var id: String { rawValue }
  var title: String {
    switch self {
    case .knock: return "Knock · 3–3–4"
    case .steady: return "Steady · 10 taps"
    case .heartbeat: return "Heartbeat · 2–2–2"
    case .custom: return "Custom"
    }
  }
}

enum VibrationStrength: Int, Codable, CaseIterable, Identifiable {
  case gentle = 4
  case firm = 6
  var id: Int { rawValue }
  var title: String { self == .gentle ? "Gentle" : "Firm" }
}

struct VibrationPattern: Codable, Equatable {
  var groupsText = "3, 3, 4"
  var interval = 0.15
  var pause = 0.45
  var strength = VibrationStrength.firm

  var groups: [Int]? {
    let tokens = groupsText.split(whereSeparator: {
      $0.isWhitespace || [",", "–", "—"].contains(String($0))
    })
    guard !tokens.isEmpty, tokens.count <= 24 else { return nil }
    var values: [Int] = []
    for token in tokens {
      guard token.allSatisfy({ $0.isNumber }), let value = Int(token), (1...24).contains(value)
      else { return nil }
      values.append(value)
    }
    guard values.reduce(0, +) <= 24 else { return nil }
    return values
  }
  var taps: Int { groups?.reduce(0, +) ?? 0 }
  var delays: [Int] {
    guard let groups else { return [] }
    var result: [Int] = []
    for (index, count) in groups.enumerated() {
      for tap in 0..<count {
        let delay = tap < count - 1 ? interval : index < groups.count - 1 ? pause : 0.16
        result.append(Int((delay * 1000).rounded()))
      }
    }
    return result
  }
  var duration: Double { Double(delays.reduce(0, +)) / 1000 }
  var error: String? {
    guard groups != nil else { return "Enter groups of 1–24 taps, up to 24 taps total." }
    guard interval.isFinite, pause.isFinite, (0.06...0.30).contains(interval),
      (0.08...0.60).contains(pause)
    else { return "Choose a tap interval and group pause within the slider ranges." }
    guard duration <= 2.8 else {
      return "Shorten the pauses or use fewer taps to finish before sleep."
    }
    return nil
  }
  var summary: String { "\(taps) taps · \(String(format: "%.1f", duration)) seconds" }
  var rhythm: String { groups?.map(String.init).joined(separator: "–") ?? "Custom" }
  var reminderLabel: String {
    preset == .custom
      ? "\(taps)-tap reminder · Custom pattern" : "\(taps)-tap reminder · \(rhythm) rhythm"
  }
  var argument: String { delays.map { "\(strength.rawValue):\($0)" }.joined(separator: ",") }
  var preset: VibrationPreset {
    for preset in [VibrationPreset.knock, .steady, .heartbeat] {
      let value = Self.make(preset)
      if groups == value.groups && abs(interval - value.interval) < 0.001
        && abs(pause - value.pause) < 0.001
      {
        return preset
      }
    }
    return .custom
  }
  static func make(_ preset: VibrationPreset) -> Self {
    switch preset {
    case .knock, .custom: return Self()
    case .steady: return Self(groupsText: "10", interval: 0.18, pause: 0.45)
    case .heartbeat: return Self(groupsText: "2, 2, 2", interval: 0.12, pause: 0.40)
    }
  }
  static func load(from defaults: UserDefaults = .standard) -> Self {
    guard let data = defaults.data(forKey: "vibrationPattern"),
      let value = try? JSONDecoder().decode(Self.self, from: data), value.error == nil
    else { return Self() }
    return value
  }
  func save(to defaults: UserDefaults = .standard) {
    guard error == nil, let data = try? JSONEncoder().encode(self) else { return }
    defaults.set(data, forKey: "vibrationPattern")
  }
}
