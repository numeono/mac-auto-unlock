import AppKit
import ApplicationServices
import CoreGraphics
import Security
import OpenDirectory
import Darwin

let appID = "local.mads.MacSessionHelper"
let fm = FileManager.default
let base = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacSessionHelper")
let socketPath = base.appendingPathComponent("control.sock").path
let configURL = base.appendingPathComponent("config.json")
let recoveryURL = base.appendingPathComponent("relock.json")
let failureURL = base.appendingPathComponent("unlock-blocked")

func session() -> SessionState? {
    guard let d = CGSessionCopyCurrentDictionary() as? [String: Any],
          let uid = d["kCGSSessionUserIDKey"] as? NSNumber,
          let ident = d["CGSSessionUniqueSessionUUID"] as? String else { return nil }
    return SessionState(uid: uid.uint32Value,
        loginDone: (d["kCGSessionLoginDoneKey"] as? NSNumber)?.boolValue == true,
        onConsole: (d["kCGSSessionOnConsoleKey"] as? NSNumber)?.boolValue == true,
        identity: ident,
        locked: (d["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue == true)
}

func secureDirectory() throws {
    if !fm.fileExists(atPath: base.path) {
        try fm.createDirectory(at: base, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
    }
    var st = stat()
    guard lstat(base.path, &st) == 0, st.st_uid == getuid(),
          (st.st_mode & S_IFMT) == S_IFDIR, (st.st_mode & 0o077) == 0 else {
        throw SessionError.unsafeSession
    }
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try data.write(to: url, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
func readJSON(_ url: URL) -> [String: Any] {
    guard let data = try? Data(contentsOf: url),
          let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return d
}

func keychainQuery() -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: appID,
     kSecAttrAccount as String: NSUserName(),
     kSecAttrSynchronizable as String: false]
}
func passwordData() throws -> Data {
    // Never prompt during an automated task, and never unlock a Keychain ourselves.
    SecKeychainSetUserInteractionAllowed(false)
    defer { SecKeychainSetUserInteractionAllowed(true) }
    var q = keychainQuery()
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data, !data.isEmpty else { throw SessionError.credential }
    return data
}
func hasCredential() -> Bool {
    SecKeychainSetUserInteractionAllowed(false)
    defer { SecKeychainSetUserInteractionAllowed(true) }
    var q = keychainQuery()
    q[kSecReturnAttributes as String] = true
    return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
}
func savePassword(_ password: String) throws {
    var access: SecAccess?
    let accessCode = SecAccessCreate("Mac Session Helper login password" as CFString, nil, &access)
    guard accessCode == errSecSuccess, let access else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(accessCode))
    }
    var bytes = Data(password.utf8)
    defer { bytes.resetBytes(in: 0..<bytes.count) }
    let q = keychainQuery()
    let attrs: [String: Any] = [kSecValueData as String: bytes, kSecAttrAccess as String: access]
    var code = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
    if code == errSecItemNotFound {
        var add = q.merging(attrs) { _, new in new }
        add[kSecAttrLabel as String] = "Mac Session Helper (local session only)"
        code = SecItemAdd(add as CFDictionary, nil)
    }
    guard code == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(code)) }
}

func lockScreen() -> Bool {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW) else { return false }
    defer { dlclose(handle) }
    guard let sym = dlsym(handle, "SACLockScreenImmediate") else { return false }
    typealias LockFunction = @convention(c) () -> Int32
    return unsafeBitCast(sym, to: LockFunction.self)() == 0
}

func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key, &value) == .success else { return nil }
    return value
}

// Diagnostic metadata only. Never read AXValue, field text, or account names.
func focusDiagnostic() -> [String: Any] {
    let root = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value)
    var info: [String: Any] = ["focused_element_result": result.rawValue]
    if let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
        let field = unsafeBitCast(value, to: AXUIElement.self)
        var pid: pid_t = 0
        info["pid_result"] = AXUIElementGetPid(field, &pid).rawValue
        info["bundle"] = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unavailable"
        info["role"] = attribute(field, kAXRoleAttribute as CFString) as? String ?? "unavailable"
        info["subrole"] = attribute(field, kAXSubroleAttribute as CFString) as? String ?? "unavailable"
    }
    return info
}

func passwordFieldIsFocused() -> Bool {
    guard let focus = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString),
          CFGetTypeID(focus) == AXUIElementGetTypeID() else { return false }
    let field = unsafeBitCast(focus, to: AXUIElement.self)
    var pid: pid_t = 0
    guard AXUIElementGetPid(field, &pid) == .success,
          isTrustedLoginwindow(pid: pid) else { return false }
    let role = attribute(field, kAXRoleAttribute as CFString) as? String
    let subrole = attribute(field, kAXSubroleAttribute as CFString) as? String
    return role == (kAXTextFieldRole as String) && subrole == (kAXSecureTextFieldSubrole as String)
}

// Focus only one unambiguous secure field belonging to Apple's loginwindow.
// Never inspect AXValue or infer a password target from screen coordinates.
func focusLoginPasswordField() -> Bool {
    guard session()?.locked == true else { return false }
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow")
    guard apps.count == 1, let app = apps.first,
          isTrustedLoginwindow(pid: app.processIdentifier) else { return false }
    var queue = [AXUIElementCreateApplication(app.processIdentifier)]
    var visited: [AXUIElement] = []
    var candidates: [AXUIElement] = []
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    while !queue.isEmpty && visited.count < 256 {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
        let element = queue.removeFirst()
        if visited.contains(where: { CFEqual($0, element) }) { continue }
        visited.append(element)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else { continue }
        let role = attribute(element, kAXRoleAttribute as CFString) as? String
        let subrole = attribute(element, kAXSubroleAttribute as CFString) as? String
        if role == (kAXTextFieldRole as String), subrole == (kAXSecureTextFieldSubrole as String),
           (attribute(element, kAXEnabledAttribute as CFString) as? Bool) == true {
            candidates.append(element)
        }
        if let children = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
            guard children.count + queue.count + visited.count <= 256 else { return false }
            queue.append(contentsOf: children)
        }
    }
    guard queue.isEmpty, candidates.count == 1, session()?.locked == true else { return false }
    return AXUIElementSetAttributeValue(candidates[0], kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
}

func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
        waitForSystemUpdates(0.05)
    }
}

final class Helper: NSObject, NSApplicationDelegate {
    var book = LeaseBook()
    var identity = ""
    var timer: Timer?
    var menuItem: NSStatusItem?
    var enabled = false
    var configuring = false
    var lastError: String? = nil
    var listener: Int32 = -1
    var idleLockEnabled = false
    var lastTaskActivity: Double = 0
    var statusWindow: NSWindow?
    var statusLabel: NSTextField?
    var unlockInProgress = false
    var cancelUnlock = false

    func eligible() -> Bool { session()?.eligible(uid: getuid(), identity: identity) == true }
    var now: Double { ProcessInfo.processInfo.systemUptime }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard getuid() != 0, let s = session(), s.loginDone, s.uid == getuid(), !s.identity.isEmpty else { exit(3) }
        identity = s.identity
        lastTaskActivity = now
        // Bound each Accessibility IPC call so stale targets cannot freeze
        // the command handler and its relock timer indefinitely.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        do { try secureDirectory() } catch { exit(4) }
        let config = readJSON(configURL)
        enabled = config["enabled"] as? Bool == true
        idleLockEnabled = config["idleLock"] as? Bool == true
        // Never restore leases or unlock at launch. A restart can only relock a
        // desktop this helper previously unlocked in THIS login session.
        let recovery = readJSON(recoveryURL)
        if recovery["session"] as? String == identity {
            book.ownsUnlock = true
            try? relock()
        } else { try? fm.removeItem(at: recoveryURL) }
        buildMenu()
        do { try startServer() } catch { exit(5) }
        let watchdog = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        timer = watchdog
        for mode in [RunLoop.Mode.default, .modalPanel, .eventTracking] {
            RunLoop.main.add(watchdog, forMode: mode)
        }
        // A logout terminates this Aqua LaunchAgent. No system daemon is installed.
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Activating an enrolled app must not start password setup again.
        // Repairs use the explicit CLI setup command or the menu action.
        if !configuring { showStatus() }
        return true
    }

    func buildMenu() {
        menuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuItem?.button?.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Mac Auto Unlock")
        let menu = NSMenu()
        for (title, action) in [("Session status…", #selector(showStatus)),
                                ("Set up / update password…", #selector(setup)),
                                ("Pause unlocking and lock", #selector(pauseFromMenu)),
                                ("Resume unlocking", #selector(resumeFromMenu)),
                                ("Lock now", #selector(lockFromMenu))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        menuItem?.menu = menu
    }

    @objc func showStatus() {
        guard !unlockInProgress else { return }
        if statusWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 310),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Mac Auto Unlock"
            window.isReleasedWhenClosed = false
            let title = NSTextField(labelWithString: "Temporary desktop access")
            title.font = .boldSystemFont(ofSize: 21)
            title.frame = NSRect(x: 24, y: 256, width: 410, height: 30)
            window.contentView?.addSubview(title)
            let label = NSTextField(wrappingLabelWithString: "")
            label.font = .systemFont(ofSize: 13)
            label.frame = NSRect(x: 24, y: 76, width: 410, height: 170)
            window.contentView?.addSubview(label)
            statusLabel = label
            let setupButton = NSButton(title: "Password setup…", target: self, action: #selector(setup))
            setupButton.frame = NSRect(x: 20, y: 22, width: 165, height: 32)
            let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(showStatus))
            refreshButton.frame = NSRect(x: 330, y: 22, width: 105, height: 32)
            window.contentView?.addSubview(setupButton)
            window.contentView?.addSubview(refreshButton)
            window.center()
            statusWindow = window
        }
        let blocked = fm.fileExists(atPath: failureURL.path)
        let readiness = blocked ? "Local password setup is required after an unsuccessful unlock."
            : (!AXIsProcessTrusted() ? "Enable this installed app in Device Control and Data Access."
               : (!hasCredential() ? "Save your Mac password locally to enable task access."
                  : "Configured. A successful live test is still required after updates."))
        statusLabel?.stringValue = "\(readiness)\n\nDesktop: \(session()?.locked == true ? "locked" : "unlocked")\nActive tasks: \(book.leases.count)\nAutomatic unlocking: \(enabled ? "enabled" : "paused")\n\nTasks last at most 15 minutes. Initial login after shutdown remains manual. Version 1.0.6."
        statusWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func persistConfig() throws {
        try writeJSON(["enabled": enabled, "idleLock": idleLockEnabled, "idleSeconds": 900], to: configURL)
    }
    func markOwned() throws {
        try writeJSON(["session": identity], to: recoveryURL)
        book.ownsUnlock = true
    }
    func relock() throws {
        guard eligible() else { throw SessionError.unsafeSession }
        if session()?.locked != true {
            guard lockScreen() else { throw SessionError.lockFailed }
            for _ in 0..<30 {
                if session()?.locked == true { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard session()?.locked == true else { throw SessionError.lockFailed }
        }
        book.clear()
        try? fm.removeItem(at: recoveryURL)
    }
    func tick() {
        guard eligible(), !unlockInProgress else { return }
        book.expire(now: now)
        if session()?.locked == true {
            // External/manual locking revokes every existing lease. A renewal
            // can never unlock it again.
            book.clear()
            try? fm.removeItem(at: recoveryURL)
        } else if book.shouldRelock || (idleLockEnabled && now - lastTaskActivity >= 900 &&
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!) >= 900) {
            if configuring {
                NSApp.abortModal()
                NSApp.modalWindow?.orderOut(nil)
            }
            do { try relock(); lastError = nil } catch { lastError = message(error) }
        }
    }
    func recordUnlock(stage: String, elapsed: Double, samples: Int) {
        // Bounded diagnostic snapshot: no field values, account names or credentials.
        try? writeJSON(["time": ISO8601DateFormatter().string(from: Date()),
                        "stage": stage, "elapsed_seconds": elapsed, "focus_samples": samples,
                        "focus": focusDiagnostic(), "display_awake": displayIsAwake(),
                        "locked": session()?.locked as Any? ?? NSNull()],
                       to: base.appendingPathComponent("last-unlock.json"))
    }
    func unlock() throws {
        guard !unlockInProgress else { throw SessionError.invalidRequest }
        unlockInProgress = true
        cancelUnlock = false
        defer { unlockInProgress = false }
        guard eligible() else { throw SessionError.unsafeSession }
        guard enabled else { throw SessionError.disabled }
        guard !fm.fileExists(atPath: failureURL.path) else { throw SessionError.unlockFailed }
        guard AXIsProcessTrusted() else { throw SessionError.accessibility }
        guard session()?.locked == true else { return }
        // Wake transitions can take several seconds. Wait for a stable secure
        // loginwindow field, never relaxing the target or session checks.
        let started = now
        guard wakeDisplay(eligible: { self.eligible() && self.enabled && !self.cancelUnlock }, report: { details in
            try? writeJSON(details, to: base.appendingPathComponent("last-wake.json"))
        }) else {
            recordUnlock(stage: "display_wake_timeout", elapsed: now - started, samples: 0)
            throw SessionError.displayWake
        }
        let focusStarted = now
        var focus = StableFocus()
        var dismissedSaver = false
        var requestedFocus = false
        var samples = 0
        key(0x38) // Shift: wake without entering text.
        while true {
            guard eligible(), enabled, !cancelUnlock else { throw SessionError.unsafeSession }
            // The owner (or native grace period) may unlock during the wake.
            if session()?.locked == false {
                recordUnlock(stage: "unlocked_during_wake", elapsed: now - started, samples: samples)
                return
            }
            let focused = displayIsAwake() && passwordFieldIsFocused()
            samples += 1
            if focus.observe(focused, at: now) { break }
            if now - focusStarted >= 8 {
                recordUnlock(stage: "secure_focus_timeout", elapsed: now - started, samples: samples)
                throw SessionError.inputTarget
            }
            if !focused && !dismissedSaver && now - focusStarted >= 2 {
                key(0x35) // Escape, only while no secure field is focused.
                dismissedSaver = true
            }
            if !focused && !requestedFocus && now - focusStarted >= 3 {
                requestedFocus = true
                if eligible(), session()?.locked == true { _ = focusLoginPasswordField() }
            }
            waitForSystemUpdates(0.1)
        }
        guard eligible(), enabled, !cancelUnlock, session()?.locked == true, displayIsAwake(), passwordFieldIsFocused() else { throw SessionError.inputTarget }
        recordUnlock(stage: "secure_focus_verified", elapsed: now - started, samples: samples)
        // Retrieve the credential only after the input target is verified.
        var bytes = try passwordData()
        defer { bytes.resetBytes(in: 0..<bytes.count) }
        guard let string = String(data: bytes, encoding: .utf8) else { throw SessionError.credential }
        var chars = Array(string.utf16)
        defer { _ = chars.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        guard chars.count <= 1024 else { throw SessionError.credential }
        try markOwned()
        // Persist before typing. A failed attempt or crash must not create a
        // password retry loop. Only local setup clears this latch.
        try Data("Unlock attempt needs verification\n".utf8).write(to: failureURL, options: .atomic)
        var attemptCompleted = false
        var stage = "before_field_clear"
        defer {
            if !attemptCompleted {
                recordUnlock(stage: stage, elapsed: now - started, samples: samples)
            }
        }
        func requireSecureFocus() throws {
            guard now - started < 40 else { throw SessionError.interruptedInput }
            let deadline = now + 2
            var stable = StableFocus()
            while now < deadline {
                guard eligible(), enabled, !cancelUnlock, session()?.locked == true, displayIsAwake() else { throw SessionError.interruptedInput }
                if stable.observe(passwordFieldIsFocused(), at: now) { return }
                waitForSystemUpdates(0.05)
            }
            throw SessionError.interruptedInput
        }
        try requireSecureFocus()
        key(0, flags: .maskCommand) // Select any existing password-field content.
        stage = "after_select_all"
        try requireSecureFocus()
        key(0x33) // Delete
        stage = "after_field_clear"
        try requireSecureFocus()
        for offset in stride(from: 0, to: chars.count, by: 20) {
            try requireSecureFocus()
            stage = "password_input_started"
            let count = min(20, chars.count - offset)
            let source = CGEventSource(stateID: .hidSystemState)
            let event = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: true)
            event?.flags = [] // Never inherit Command/Shift from earlier events.
            chars.withUnsafeBufferPointer { buffer in
                event?.keyboardSetUnicodeString(stringLength: count, unicodeString: buffer.baseAddress! + offset)
            }
            event?.post(tap: .cghidEventTap)
            waitForSystemUpdates(0.05)
            let release = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: false)
            release?.flags = []
            release?.post(tap: .cghidEventTap)
            waitForSystemUpdates(0.1)
        }
        stage = "before_submit"
        try requireSecureFocus()
        key(0x24) // Return
        stage = "awaiting_unlock"
        for _ in 0..<150 {
            waitForSystemUpdates(0.1)
            guard enabled, !cancelUnlock else { throw SessionError.interruptedInput }
            if eligible(), session()?.locked == false {
                try? fm.removeItem(at: failureURL)
                recordUnlock(stage: "unlock_verified", elapsed: now - started, samples: samples)
                attemptCompleted = true
                return
            }
        }
        throw SessionError.unlockFailed
    }

    @objc func setup() {
        guard eligible(), session()?.locked == false, !configuring, !unlockInProgress else { return }
        configuring = true
        defer { configuring = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Set up Mac Auto Unlock"
        alert.informativeText = "Enter this Mac account's password. It stays in the local login Keychain and is used only when a desktop task explicitly requests an unlock.\n\nThe helper locks the screen after 15 minutes of idle time. After a restart, it resumes when macOS starts your desktop session. macOS handles FileVault and account sign-in."
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 370, height: 25))
        defer { input.stringValue = "" }
        input.placeholderString = "Mac login password"
        alert.accessoryView = input
        alert.addButton(withTitle: "Save locally")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var password = input.stringValue
        input.stringValue = ""
        defer { password = "" }
        guard !password.isEmpty else { return }
        var setupStage = "reading the local account"
        do {
            guard password.utf16.count <= 1024 else { throw SessionError.invalidRequest }
            let node = try ODNode(session: ODSession.default(), type: UInt32(kODNodeTypeLocalNodes))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
            setupStage = "verifying the Mac password"
            try record.verifyPassword(password)
            setupStage = "saving the password in Keychain"
            try savePassword(password)
            enabled = true
            idleLockEnabled = true
            setupStage = "saving helper settings"
            try persistConfig()
            try? fm.removeItem(at: failureURL)
            lastError = nil
            try? writeJSON(["time": ISO8601DateFormatter().string(from: Date()), "ok": true],
                           to: base.appendingPathComponent("last-setup.json"))
            let done = NSAlert()
            done.messageText = "Password saved locally"
            done.informativeText = AXIsProcessTrusted()
                ? "The helper is ready for a lock/unlock test."
                : "Next, allow the installed app in System Settings → Privacy & Security → Accessibility. Then return to Codex for the lock/unlock test."
            done.runModal()
        } catch {
            let e = error as NSError
            // Domain/code only. Never persist localized descriptions or userInfo,
            // which can contain account details. Never persist password input.
            lastError = "Setup failed while \(setupStage). Error \(e.domain) \(e.code)."
            try? writeJSON(["time": ISO8601DateFormatter().string(from: Date()), "ok": false,
                            "stage": setupStage, "domain": e.domain, "code": e.code],
                           to: base.appendingPathComponent("last-setup.json"))
            let a = NSAlert(); a.messageText = "Setup was not completed"; a.informativeText = lastError!; a.runModal()
        }
    }
    @objc func pauseFromMenu() { _ = handle(["command": "pause"]) }
    @objc func resumeFromMenu() {
        guard eligible(), !unlockInProgress, session()?.locked == false, hasCredential(), !fm.fileExists(atPath: failureURL.path) else { return }
        enabled = true; try? persistConfig()
    }
    @objc func lockFromMenu() { _ = handle(["command": "lock"]) }

    func status() -> [String: Any] {
        let s = session()
        return ["ok": true, "version": "1.0.6", "eligible_session": eligible(),
                "locked": s?.locked as Any? ?? NSNull(), "enabled": enabled,
                "credential_saved": hasCredential(), "accessibility": AXIsProcessTrusted(),
                "attempt_blocked": fm.fileExists(atPath: failureURL.path),
                "active_tasks": book.leases.count, "helper_unlocked_desktop": book.ownsUnlock,
                "idle_lock_seconds": idleLockEnabled ? 900 : 0,
                "last_error": lastError as Any? ?? NSNull(), "setup_open": configuring,
                "display_awake": displayIsAwake(),
                "supports_cold_boot_unlock": false, "supports_automatic_login": false]
    }

    func handle(_ request: [String: Any]) -> [String: Any] {
        do {
            let command = request["command"] as? String ?? ""
            if command == "status" { return status() }
            guard eligible() else { throw SessionError.unsafeSession }
            if unlockInProgress {
                guard command == "lock" || command == "pause" else { throw SessionError.invalidRequest }
                cancelUnlock = true
            }
            if command == "setup" {
                guard session()?.locked == false else { throw SessionError.unsafeSession }
                DispatchQueue.main.async { self.setup() }
                return ["ok": true, "message": "Local secure setup window requested."]
            }
            if command == "request-permissions" {
                guard session()?.locked == false else { throw SessionError.unsafeSession }
                let option = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                let granted = AXIsProcessTrustedWithOptions([option: true] as CFDictionary)
                return ["ok": true, "accessibility": granted, "message": "Accessibility permission requested from macOS."]
            }
            // Releasing a lease is safe during local setup. Relock is deferred
            // to the timer, which also closes an idle modal before locking.
            if command == "end" && configuring {
                try book.end(token: request["lease"] as? String ?? "")
                return status()
            }
            guard !configuring else { throw SessionError.notConfigured }
            switch command {
            case "wake-check":
                var details: [String: Any] = [:]
                let ready = wakeDisplay(eligible: { self.eligible() }, report: { details = $0 })
                try? writeJSON(details, to: base.appendingPathComponent("last-wake.json"))
                return ["ok": ready, "wake": details, "password_attempted": false]
            case "begin":
                guard hasCredential() else { throw SessionError.notConfigured }
                guard enabled else { throw SessionError.disabled }
                let ttl = request["seconds"] as? Double ?? 900
                let token = UUID().uuidString
                var proposed = book
                let wasLocked = session()?.locked == true
                if wasLocked { proposed.clear() }
                proposed.expire(now: now)
                try proposed.begin(token: token, ttl: ttl, now: now)
                if wasLocked { try unlock() }
                proposed.ownsUnlock = book.ownsUnlock
                book = proposed
                lastTaskActivity = now
                lastError = nil
                return ["ok": true, "lease": token, "seconds": ttl, "unlocked": wasLocked]
            case "renew":
                guard session()?.locked == false else { book.clear(); throw SessionError.unknownLease }
                try book.renew(token: request["lease"] as? String ?? "", ttl: request["seconds"] as? Double ?? 900, now: now)
                lastTaskActivity = now
            case "end":
                try book.end(token: request["lease"] as? String ?? "")
                if book.shouldRelock { try relock() }
            case "lock": try relock()
            case "pause":
                enabled = false; try persistConfig(); try relock()
            case "test-cycle":
                guard enabled, hasCredential() else { throw SessionError.notConfigured }
                guard AXIsProcessTrusted() else { throw SessionError.accessibility }
                guard book.leases.isEmpty, session()?.locked == false else { throw SessionError.invalidRequest }
                var check = try passwordData(); check.resetBytes(in: 0..<check.count)
                guard !fm.fileExists(atPath: failureURL.path) else { throw SessionError.unlockFailed }
                try relock()
                try unlock()
                try relock()
                lastError = nil
                return ["ok": true, "locked_then_unlocked_then_relocked": true]
            default: throw SessionError.invalidRequest
            }
            lastError = nil
            return status()
        } catch {
            lastError = message(error)
            return ["ok": false, "error": message(error)]
        }
    }

    func startServer() throws {
        let lockPath = base.appendingPathComponent("daemon.lock").path
        let lockFD = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw SessionError.unsafeSession }
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw SessionError.unsafeSession }
        unlink(socketPath)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let count = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < count else { throw SessionError.invalidRequest }
        withUnsafeMutablePointer(to: &address.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: count) { p in
                _ = socketPath.withCString { strlcpy(p, $0, count) }
            }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        address.sun_len = UInt8(length)
        let rc = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, length) }
        }
        guard rc == 0, chmod(socketPath, 0o600) == 0, listen(listener, 8) == 0 else { throw SessionError.unsafeSession }
        let listeningFD = listener
        DispatchQueue.global(qos: .utility).async {
            while true {
                let fd = accept(listeningFD, nil, nil)
                if fd < 0 { continue }
                var peerUID: uid_t = 0, peerGID: gid_t = 0
                guard getpeereid(fd, &peerUID, &peerGID) == 0, peerUID == getuid() else { close(fd); continue }
                var timeout = timeval(tv_sec: 3, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var noSignal: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
                let deadline = ProcessInfo.processInfo.systemUptime + 3
                while data.count <= maximumRequestBytes {
                    let remaining = deadline - ProcessInfo.processInfo.systemUptime
                    guard remaining > 0 else { break }
                    var readiness = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                    guard poll(&readiness, 1, Int32(remaining * 1000)) > 0 else { break }
                    let n = read(fd, &buffer, buffer.count)
                    if n <= 0 { break }
                    data.append(contentsOf: buffer.prefix(n))
                    if data.contains(10) { break }
                }
                var response: [String: Any] = ["ok": false, "error": "Invalid request."]
                if let request = validatedRequest(data) {
                    let finished = DispatchSemaphore(value: 0)
                    onMainRunLoop {
                        response = self.handle(request)
                        finished.signal()
                    }
                    finished.wait()
                }
                if var output = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) {
                    output.append(10)
                    output.withUnsafeBytes { p in
                        var offset = 0
                        while offset < p.count {
                            let n = write(fd, p.baseAddress! + offset, p.count - offset)
                            if n <= 0 { break }; offset += n
                        }
                    }
                }
                close(fd)
            }
        }
    }
}

func message(_ error: Error) -> String {
    (error as? SessionError)?.rawValue ?? "Local operation failed. No credential details were logged."
}

// No command-line password input, credential output, preboot mode, or system
// service mode exists. This executable runs only as the user's GUI helper.
guard CommandLine.arguments.count == 1 else { exit(2) }
umask(0o077)
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let helper = Helper()
application.delegate = helper
application.run()
