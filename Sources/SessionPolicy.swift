import Foundation

struct SessionPolicy {
  private(set) var started: TimeInterval?
  private(set) var lastHeartbeat: TimeInterval = 0
  private(set) var duration = 0
  private var closedSince: TimeInterval?
  var active: Bool { started != nil }

  mutating func begin(now: TimeInterval, duration: Int) -> Bool {
    guard !active, duration >= 0, duration <= 86400 else { return false }
    started = now
    lastHeartbeat = now
    self.duration = duration
    closedSince = nil
    return true
  }
  mutating func heartbeat(now: TimeInterval) { lastHeartbeat = now }
  mutating func end() {
    started = nil
    closedSince = nil
  }
  func remaining(now: TimeInterval) -> Int? {
    guard let started, duration > 0 else { return nil }
    return max(0, Int(ceil(TimeInterval(duration) - (now - started))))
  }
  mutating func stopReason(now: TimeInterval, lidClosed: Bool?) -> String? {
    guard let started else { return nil }
    guard let lidClosed else { return "Lid sensor unavailable. Normal sleep restored." }
    if now - lastHeartbeat >= 10 { return "App stopped responding. Normal sleep restored." }
    if duration > 0 && now - started >= TimeInterval(duration) {
      return "Timer finished. Normal sleep restored."
    }
    if lidClosed {
      if closedSince == nil { closedSince = now }
      if now - (closedSince ?? now) >= 4 { return "Lid closed. Normal sleep restored." }
    } else {
      closedSince = nil
    }
    return nil
  }
}
