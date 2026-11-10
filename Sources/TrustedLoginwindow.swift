import AppKit
import Security

// A bundle identifier alone is caller-controlled. Require Apple's signature
// and the system executable path before accepting a password-input target.
func isTrustedLoginwindow(pid: pid_t) -> Bool {
    guard pid > 0,
          let app = NSRunningApplication(processIdentifier: pid),
          app.bundleIdentifier == "com.apple.loginwindow",
          app.executableURL?.standardizedFileURL.path ==
            "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow" else { return false }
    var code: SecCode?
    let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
          let code else { return false }
    var requirement: SecRequirement?
    guard SecRequirementCreateWithString(
        "identifier \"com.apple.loginwindow\" and anchor apple" as CFString,
        [], &requirement) == errSecSuccess, let requirement else { return false }
    return SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
}
