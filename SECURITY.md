# Security model

Mac Session Helper stores a usable login password in the local login Keychain so a task can unlock an existing desktop session. Accessibility permission allows powerful interaction with that desktop. This is experimental security-sensitive software, not a replacement for macOS authentication or a hardened boundary against the current user.

## Trusted parties

The account owner, macOS, the installed helper, its signing identity and every process already running as that user are within the trust boundary. The Unix socket and runtime directory exclude other ordinary users through filesystem permissions and peer-UID verification. Same-user code and root can request unlocks or tamper with this environment. There is no per-client application allowlist.

The helper requires an eligible already-logged-in console session. Before password input it checks the system loginwindow executable path, Apple's code signature, secure-field role, focus and display state. It never intentionally types into a generic window or unverified target. Focus and event delivery remain separate operations; a check cannot eliminate every race.

## Credential handling

Local setup verifies the password against the local account, then writes a non-synchronizing Keychain item. Apple's legacy ACL creation defaults to trusting the creating application. Automated reads disable Keychain interaction so they cannot display an unseen permission prompt. No password-bearing command, response, configuration file, diagnostic or clipboard operation exists.

Mutable byte buffers are cleared, but Swift strings and framework copies prevent a guarantee of complete memory zeroization. Do not collect process dumps during enrollment or unlock. Do not attach Keychain exports, runtime directories, screenshots containing secrets, account identifiers or authentication logs to issues.

## Failures

A persistent latch is written before input. An unsuccessful attempt leaves it set; only successful local setup or a verified successful attempt clears it. Missing target information causes a stop. Display-only failures before credential use do not initiate a password attempt.

Leases are bounded and the helper relocks after the final lease it owns ends. A timer handles idle/expired leases, including modal setup. Bounded waits process system events and reject reentrant mutations during unlock. A hung OS service or a stopped helper can still delay enforcement; an independently enforcing watchdog is not implemented. Do not promise an absolute lock deadline under arbitrary process or OS failure.

FileVault, automatic login and preboot authentication are untouched. The app starts as a user Aqua LaunchAgent after macOS establishes a graphical login session. It can unlock that session's screen and has no role in establishing the session.

## Reporting and disclosure

While the repository is private, report findings to its owner through a private issue. Include the version, macOS version and sanitized reproduction steps. Never include passwords, secret exports or raw memory dumps. A public reporting channel and disclosure policy must be established before publication.

The [audit report](docs/SECURITY-AUDIT.md) describes the review scope, known risks and outstanding validation. It is an implementation review by the development assistant, not an independent penetration test or security certification.
