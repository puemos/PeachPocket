import Foundation

@main struct PolicyTests {
  static func check(_ label: String, _ test: () -> Bool) {
    guard test() else { fatalError("FAIL " + label) }
    print("PASS " + label)
  }
  static func main() {
    check("timer and remaining use elapsed time") {
      var p = SessionPolicy()
      guard p.begin(now: 100, duration: 30), p.remaining(now: 105) == 25 else { return false }
      p.heartbeat(now: 129)
      return p.stopReason(now: 130, lidClosed: false)?.contains("Timer finished") == true
    }
    check("indefinite session") {
      var p = SessionPolicy()
      _ = p.begin(now: 0, duration: 0)
      p.heartbeat(now: 100000)
      return p.remaining(now: 100000) == nil && p.stopReason(now: 100000, lidClosed: false) == nil
    }
    check("closed lid grace period") {
      var p = SessionPolicy()
      _ = p.begin(now: 0, duration: 1800)
      return p.stopReason(now: 1, lidClosed: true) == nil
        && p.stopReason(now: 4.99, lidClosed: true) == nil
        && p.stopReason(now: 5, lidClosed: true)?.contains("Lid closed") == true
    }
    check("reopen cancels lid countdown") {
      var p = SessionPolicy()
      _ = p.begin(now: 0, duration: 1800)
      _ = p.stopReason(now: 1, lidClosed: true)
      _ = p.stopReason(now: 4, lidClosed: false)
      return p.stopReason(now: 5, lidClosed: true) == nil
        && p.stopReason(now: 8, lidClosed: true) == nil
        && p.stopReason(now: 9, lidClosed: true)?.contains("Lid closed") == true
    }
    check("missing sensor fails closed") {
      var p = SessionPolicy()
      _ = p.begin(now: 0, duration: 1800)
      return p.stopReason(now: 1, lidClosed: nil)?.contains("sensor unavailable") == true
    }
    check("stalled app expires after ten seconds") {
      var p = SessionPolicy()
      _ = p.begin(now: 0, duration: 1800)
      p.heartbeat(now: 5)
      return p.stopReason(now: 14.99, lidClosed: false) == nil
        && p.stopReason(now: 15, lidClosed: false)?.contains("stopped responding") == true
    }
    check("negative and excessive timers rejected") {
      var p = SessionPolicy()
      return !p.begin(now: 0, duration: -1) && !p.begin(now: 0, duration: 86401) && !p.active
    }
    check("second session cannot replace active session") {
      var p = SessionPolicy()
      _ = p.begin(now: 0, duration: 1800)
      return !p.begin(now: 100, duration: 3600) && p.remaining(now: 100) == 1700
    }
    check("ended session cannot trigger restoration again") {
      var p = SessionPolicy()
      _ = p.begin(now: 0, duration: 1800)
      p.end()
      return !p.active && p.remaining(now: 100) == nil
        && p.stopReason(now: 100, lidClosed: nil) == nil
    }
    check("new session has no previous lid countdown") {
      var p = SessionPolicy()
      _ = p.begin(now: 0, duration: 1800)
      _ = p.stopReason(now: 1, lidClosed: true)
      p.end()
      _ = p.begin(now: 10, duration: 1800)
      return p.stopReason(now: 11, lidClosed: true) == nil
    }
  }
}
