import Foundation

@main struct PatternTests {
  static func check(_ label: String, _ value: @autoclosure () -> Bool) {
    precondition(value(), "FAIL " + label)
    print("PASS " + label)
  }
  static func main() {
    let knock = VibrationPattern()
    check(
      "default pattern fits the sleep grace period",
      knock.error == nil && knock.taps == 10 && knock.duration <= 2.8)
    let custom = VibrationPattern(
      groupsText: "2, 1", interval: 0.15, pause: 0.45, strength: .gentle)
    check(
      "custom groups preserve pauses and chosen strength", custom.argument == "4:150,4:450,4:160")
    check(
      "readable dash-separated patterns", VibrationPattern(groupsText: "2–2–3").groups == [2, 2, 3])
    check("empty patterns are rejected", VibrationPattern(groupsText: "").error != nil)
    check("negative tap groups are rejected", VibrationPattern(groupsText: "2, -1").error != nil)
    check("zero taps are rejected", VibrationPattern(groupsText: "2, 0").error != nil)
    check("oversized patterns are rejected", VibrationPattern(groupsText: "25").error != nil)
    check("non-numeric groups are rejected", VibrationPattern(groupsText: "3, nope").error != nil)
    check(
      "patterns cannot overrun the sleep safeguard",
      VibrationPattern(groupsText: "24", interval: 0.30).error != nil)
    check("non-finite timing is rejected", VibrationPattern(interval: .infinity).error != nil)
    check(
      "strength does not change selected preset",
      VibrationPattern(strength: .gentle).preset == .knock)
    let suite = "local.peachpocket.tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    custom.save(to: defaults)
    check("saved custom patterns survive reload", VibrationPattern.load(from: defaults) == custom)
    defaults.set(Data("invalid".utf8), forKey: "vibrationPattern")
    check(
      "damaged settings fall back to a safe default",
      VibrationPattern.load(from: defaults) == VibrationPattern())
    for preset in [VibrationPreset.knock, .steady, .heartbeat] {
      let pattern = VibrationPattern.make(preset)
      check(
        "preset \(preset.rawValue) is safe and recognizable",
        pattern.error == nil && pattern.preset == preset)
    }
  }
}
