import Foundation
import CoreGraphics
import IOKit.pwr_mgt

// Read power state, not screen contents. Unknown state must not authorize input.
func displayIsAwake() -> Bool {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0, count <= 32 else { return false }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
    return displays.prefix(Int(count)).contains { CGDisplayIsAsleep($0) == 0 }
}

// Apple's user-activity API powers the display on. Release the temporary
// assertion on return; it does not change the user's display-sleep settings.
func wakeDisplay(eligible: () -> Bool, report: ([String: Any]) -> Void = { _ in }) -> Bool {
    var details: [String: Any] = ["initial_awake": displayIsAwake(), "reason": "session_ineligible"]
    var samples = 0
    var awakeSamples = 0
    defer {
        details["samples"] = samples
        details["awake_samples"] = awakeSamples
        details["final_awake"] = displayIsAwake()
        report(details)
    }
    guard eligible() else { return false }
    var assertion: IOPMAssertionID = 0
    let result = IOPMAssertionDeclareUserActivity(
        "Mac Auto Unlock requested desktop task" as CFString,
        kIOPMUserActiveLocal, &assertion)
    details["assertion_result"] = result
    guard result == kIOReturnSuccess else { details["reason"] = "wake_request_failed"; return false }
    defer { IOPMAssertionRelease(assertion) }
    let started = ProcessInfo.processInfo.systemUptime
    var readiness = DisplayReadiness()
    while ProcessInfo.processInfo.systemUptime - started < 8 {
        guard eligible() else { details["reason"] = "session_changed"; return false }
        let awake = displayIsAwake()
        samples += 1
        if awake { awakeSamples += 1 }
        if readiness.observe(awake: awake, at: ProcessInfo.processInfo.systemUptime) {
            details["reason"] = "ready"
            return true
        }
        waitForSystemUpdates(0.1)
    }
    details["reason"] = "awake_state_timeout"
    return false
}
