import Foundation

// Explicit live power-management test. It never locks, retrieves a credential,
// synthesizes keyboard input, or changes persistent energy settings.
guard CommandLine.arguments.contains("--live-display-sleep") else {
    print("display_awake=\(displayIsAwake())")
    exit(0)
}
let command = Process()
command.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
command.arguments = ["displaysleepnow"]
try command.run()
command.waitUntilExit()
guard command.terminationStatus == 0 else { exit(2) }
let started = ProcessInfo.processInfo.systemUptime
while displayIsAwake() && ProcessInfo.processInfo.systemUptime - started < 5 {
    Thread.sleep(forTimeInterval: 0.1)
}
let observedAsleep = !displayIsAwake()
let woke = wakeDisplay(eligible: { true })
print("observed_asleep=\(observedAsleep), wake_completed=\(woke), display_awake=\(displayIsAwake())")
guard observedAsleep, woke, displayIsAwake() else { exit(3) }
print("PASS: actual sleeping display wakes and settles without any password or keyboard input")
