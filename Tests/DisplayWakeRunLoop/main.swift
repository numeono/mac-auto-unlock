import AppKit

// Run the wake test from an AppKit main-loop callback, matching the daemon.
// No credentials, locks or keyboard synthesis are used by this executable.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
onMainRunLoop {
    let command = Process()
    command.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    command.arguments = ["displaysleepnow"]
    do { try command.run() } catch { exit(2) }
    command.waitUntilExit()
    let started = ProcessInfo.processInfo.systemUptime
    while displayIsAwake() && ProcessInfo.processInfo.systemUptime - started < 3 {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
    let asleep = !displayIsAwake()
    let woke = wakeDisplay(eligible: { true })
    print("appkit_test: observed_asleep=\(asleep), wake_completed=\(woke), display_awake=\(displayIsAwake())")
    exit(asleep && woke ? 0 : 3)
}
app.run()
