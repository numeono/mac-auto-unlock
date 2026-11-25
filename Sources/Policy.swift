import Foundation

struct SessionState {
    let uid: UInt32
    let loginDone: Bool
    let onConsole: Bool
    let identity: String
    let locked: Bool

    func eligible(uid expected: UInt32, identity expectedIdentity: String) -> Bool {
        expected != 0 && uid == expected && loginDone && onConsole &&
        !identity.isEmpty && identity == expectedIdentity
    }
}

struct LeaseBook {
    static let maximumTTL: Double = 900
    var leases: [String: Double] = [:]
    var ownsUnlock = false

    mutating func begin(token: String, ttl: Double, now: Double) throws {
        guard ttl.isFinite, ttl >= 30, ttl <= Self.maximumTTL else { throw SessionError.invalidTTL }
        guard leases.count < 16 else { throw SessionError.tooManyTasks }
        leases[token] = now + ttl
    }
    mutating func renew(token: String, ttl: Double, now: Double) throws {
        guard let expiry = leases[token], expiry > now else { throw SessionError.unknownLease }
        guard ttl.isFinite, ttl >= 30, ttl <= Self.maximumTTL else { throw SessionError.invalidTTL }
        leases[token] = now + ttl
    }
    mutating func end(token: String) throws {
        guard leases.removeValue(forKey: token) != nil else { throw SessionError.unknownLease }
    }
    mutating func expire(now: Double) {
        leases = leases.filter { $0.value > now }
    }
    var shouldRelock: Bool { ownsUnlock && leases.isEmpty }
    mutating func clear() { leases.removeAll(); ownsUnlock = false }
}

enum SessionError: String, Error {
    case invalidTTL = "Lease duration must be 30 to 900 seconds."
    case tooManyTasks = "Too many active desktop tasks."
    case unknownLease = "Lease is missing or expired. Start a new task explicitly."
    case unsafeSession = "No eligible, already logged-in console session."
    case notConfigured = "Complete Mac Auto Unlock setup locally first."
    case disabled = "Unlocking is paused. Resume it locally in Mac Auto Unlock."
    case accessibility = "Grant Accessibility access to Mac Auto Unlock in System Settings."
    case credential = "The local Keychain credential is unavailable. Open local setup."
    case inputTarget = "Could not verify the loginwindow password field. No password was typed."
    case displayWake = "The display did not become ready for input. No password was typed."
    case interruptedInput = "The unlock attempt was interrupted by a session or secure-field focus change. Input may have started. Further attempts are blocked until local setup."
    case unlockFailed = "Unlock was not verified. Further attempts are blocked until local setup."
    case lockFailed = "Lock was not verified."
    case invalidRequest = "Invalid request."
}

// Require continuous focus, restarting the stability window on any loss.
struct StableFocus {
    private var since: Double?
    mutating func observe(_ focused: Bool, at now: Double) -> Bool {
        guard focused else { since = nil; return false }
        if since == nil { since = now }
        return now - since! >= 0.5
    }
}

// A stale secure AX field can remain available while the display is asleep.
// Require a continuous awake interval before even checking password focus.
struct DisplayReadiness {
    private var awakeSince: Double?
    mutating func observe(awake: Bool, at now: Double) -> Bool {
        guard awake else { awakeSince = nil; return false }
        if awakeSince == nil { awakeSince = now }
        return now - awakeSince! >= 2
    }
}
