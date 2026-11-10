import AppKit
import CoreFoundation

// Reproduce a main-queue task entering a nested AppKit modal run loop.
// A background client must receive a main-thread response before it closes.
let loop = CFRunLoopGetMain()
var replied = false
var nestedFinished = false
// Keep the mode alive, as AppKit's window event sources do in a real alert.
let keepAlive = Timer(timeInterval: 10, repeats: true) { _ in }
RunLoop.main.add(keepAlive, forMode: .modalPanel)
DispatchQueue.main.async {
    DispatchQueue.global().async {
        Thread.sleep(forTimeInterval: 0.1)
        onMainRunLoop {
            precondition(Thread.isMainThread)
            replied = true
            CFRunLoopStop(loop)
        }
    }
    CFRunLoopRunInMode(CFRunLoopMode(rawValue: RunLoop.Mode.modalPanel.rawValue as CFString), 2, false)
    precondition(replied, "Control request starved while modal setup was open")
    nestedFinished = true
    CFRunLoopStop(loop)
}
CFRunLoopRunInMode(.defaultMode, 4, false)
precondition(nestedFinished && replied)
print("PASS: background request serviced on main thread during nested modal run loop")
