import AppKit
import Darwin

guard !isTrustedLoginwindow(pid: getpid()), !isTrustedLoginwindow(pid: -1) else {
    fatalError("Non-loginwindow process accepted")
}
let windows = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow")
if let app = windows.first {
    guard isTrustedLoginwindow(pid: app.processIdentifier) else { fatalError("System loginwindow rejected") }
    print("PASS: actual system loginwindow path and Apple signature verified")
} else {
    print("SKIP: no loginwindow in this environment")
}
for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder") {
    guard !isTrustedLoginwindow(pid: app.processIdentifier) else { fatalError("Different Apple app accepted") }
}
print("PASS: current process, invalid PID and other Apple app rejected")
