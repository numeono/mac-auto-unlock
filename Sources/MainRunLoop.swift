import AppKit
import CoreFoundation

// DispatchQueue.main.sync cannot service a request while a main-queue block
// is inside NSAlert.runModal(). Schedule on the run loop instead, including
// AppKit's modal mode. The handler still executes serially on the main thread.
func onMainRunLoop(_ body: @escaping () -> Void) {
    let loop = CFRunLoopGetMain()
    let modes = [RunLoop.Mode.default.rawValue,
                 RunLoop.Mode.modalPanel.rawValue,
                 RunLoop.Mode.eventTracking.rawValue] as CFArray
    CFRunLoopPerformBlock(loop, modes, body)
    CFRunLoopWakeUp(loop)
}

// Service WindowServer/AppKit updates while waiting. The unlock caller guards
// against reentrant mutations and suspends its timer only for the bounded attempt.
func waitForSystemUpdates(_ seconds: TimeInterval) {
    guard Thread.isMainThread else { Thread.sleep(forTimeInterval: seconds); return }
    let deadline = Date(timeIntervalSinceNow: seconds)
    while Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: deadline)
    }
}
