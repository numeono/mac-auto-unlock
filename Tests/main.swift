import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
func rejects(_ action: () throws -> Void) {
    do { try action(); fatalError("Expected rejection") } catch {}
}
let valid = SessionState(uid: 501, loginDone: true, onConsole: true, identity: "session-a", locked: true)
check(valid.eligible(uid: 501, identity: "session-a"), "Locked, logged-in session must remain eligible")
for s in [
    SessionState(uid: 501, loginDone: false, onConsole: true, identity: "session-a", locked: true),
    SessionState(uid: 501, loginDone: true, onConsole: false, identity: "session-a", locked: true),
    SessionState(uid: 502, loginDone: true, onConsole: true, identity: "session-a", locked: true),
    SessionState(uid: 501, loginDone: true, onConsole: true, identity: "new-login", locked: true),
    SessionState(uid: 501, loginDone: true, onConsole: true, identity: "", locked: true)
] { check(!s.eligible(uid: 501, identity: "session-a"), "Unsafe session accepted") }
check(!valid.eligible(uid: 0, identity: "session-a"), "Root must be rejected")
var leases = LeaseBook()
check(!leases.ownsUnlock && leases.leases.isEmpty, "Restart must never restore a task")
rejects { try leases.begin(token: "x", ttl: 901, now: 0) }
rejects { try leases.begin(token: "x", ttl: .infinity, now: 0) }
rejects { try leases.begin(token: "x", ttl: -1, now: 0) }
try leases.begin(token: "a", ttl: 30, now: 10)
try leases.begin(token: "b", ttl: 60, now: 10)
leases.ownsUnlock = true
try leases.end(token: "a")
check(!leases.shouldRelock, "One task ending must not interrupt another")
leases.expire(now: 70)
check(leases.shouldRelock, "Last task expiry must relock")
rejects { try leases.renew(token: "b", ttl: 60, now: 70) }
leases.clear()
check(!leases.shouldRelock, "A manually unlocked desktop must not be claimed")
try leases.begin(token: "c", ttl: 30, now: 100)
rejects { try leases.renew(token: "c", ttl: 60, now: 130) }
leases.clear()
rejects { try leases.renew(token: "c", ttl: 60, now: 101) }
for i in 0..<16 { try leases.begin(token: "\(i)", ttl: 30, now: 0) }
rejects { try leases.begin(token: "overflow", ttl: 30, now: 0) }
print("PASS: pre-login, root, user/session switching, task limits, concurrency, expiry, renewal and revocation")

var focus = StableFocus()
check(!focus.observe(false, at: 0), "Missing focus must not authorize typing")
check(!focus.observe(true, at: 2), "Delayed focus must start stability window")
check(!focus.observe(true, at: 2.4), "Brief focus must not authorize typing")
check(!focus.observe(false, at: 2.45), "Focus loss must reset stability")
check(!focus.observe(true, at: 3), "Regained focus must wait again")
check(focus.observe(true, at: 3.5), "Stable secure focus should proceed")
print("PASS: delayed focus, unstable focus, and continuous stability window")

var display = DisplayReadiness()
check(!display.observe(awake: false, at: 0), "An asleep display must not authorize input")
check(!display.observe(awake: true, at: 10), "Waking must allow the screen to settle")
check(!display.observe(awake: true, at: 11.9), "Brief wake must not authorize input")
check(!display.observe(awake: false, at: 11.95), "Returning to sleep must reset readiness")
check(!display.observe(awake: true, at: 12), "A second wake must settle again")
check(display.observe(awake: true, at: 14), "Continuously awake display should be ready")
print("PASS: asleep display, wake settling, and sleep during settling")
