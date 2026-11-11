# Security and reliability review

Reviewed November 9, 2026. Scope: Swift helper source, Python client, shell build/install scripts, runtime boundaries, credential flow, IPC, locking policy, UI and repository contents. Candidate version: 1.0.6. This review was performed by the development assistant that changed the code. It is not an independent audit and does not establish absence of vulnerabilities.

## Findings

| ID | Severity | Finding | Treatment and evidence |
| --- | --- | --- | --- |
| MSH-01 | High | A bundle name alone did not authenticate the password target. | Candidate now checks the immutable system path and a dynamic Apple signature requirement. Native tests accept actual loginwindow and reject the test process and another Apple app. Real credential unlock and desktop access passed on November 10 and 11. Repeated reliability remains unresolved; see the validation record. |
| MSH-02 | High | Focus can change between validation and keyboard delivery. | Checks remain before each input stage. This race cannot be removed by more polling. Residual architectural risk; independent review required before public release. |
| MSH-03 | Medium | Slowly supplied socket input could monopolize the single command worker. | Candidate uses a total read deadline, bounded framing and send timeout. Parser rejects unexpected fields, malformed types and unbounded leases. Installed-helper malformed request tests passed; a drip-fed client closed in 3.3 seconds and status remained responsive. |
| MSH-04 | Medium | Setup modal bypassed lease expiry and idle enforcement; ending a lease was rejected during setup. | Candidate schedules watchdog in modal/tracking/default modes, closes idle modal before relock and accepts lease release during setup. Real timed modal/expiry test pending. |
| MSH-05 | Medium | Synthetic wake and blocking waits were unreliable with a sleeping display. | Explicit Apple power request, awake settling, event-loop waits, reentrancy guards and a password-free wake-check command added. Original 1.0.5 real helper still timed out despite standalone tests passing. Candidate passed two real helper wake-only checks from an observed sleeping display. Subsequent credential unlocks passed, but a November 10 repeat still failed at display wake before input. See the validation record. |
| MSH-06 | Medium | Rebuilding ad-hoc signed app invalidates Accessibility and Keychain trust. | Installer preserves backups and documents the required refresh. Build supports an existing stable signing identity. Developer ID/notarization and update migration remain unresolved. |
| MSH-07 | Medium | A main-thread OS service stall can postpone relock enforcement. | Accessibility messages, traversal and normal input loops are bounded. A separate watchdog is not implemented. Absolute lock deadlines under arbitrary OS/daemon failure are not guaranteed. |
| MSH-08 | Low | Setup error hid verification versus Keychain failures; activation repeatedly reopened enrollment. | Stage/domain/code diagnostics now omit raw error metadata and secrets. Activation opens status UI; enrollment is explicit. Native status-window access and Refresh were verified on November 10. |
| MSH-09 | Low | Repository lacked release hygiene and documented boundaries. | Added private repository, exclusions for runtime/build/artifacts/keys, generic documentation, audit, icon provenance and CI. No credentials or machine runtime data are intended for version control. Staged-file scan required before each push. |

## Reviewed properties

- No network client/listener, telemetry, updater, root helper, shell execution in the Swift daemon, preboot mode or credential-return API was found.
- Runtime directory must be owned by the current UID and private; socket mode is 0600 and peer UID is checked. Lock-file open refuses symlinks. Same-user tampering is outside the protection boundary.
- Keychain query is specific to this application's service and current account, with synchronization disabled. Apple's SDK states that a null trusted-app list in SecAccessCreate defaults to the creating application, not every application.
- Session identity, console ownership and completed login are required. Failure latch and no-auto-login behavior are preserved. Each task receives a separate bounded lease.
- Typed input never travels through command arguments, clipboard, diagnostic values or repository files. Transient Swift/framework password copies cannot be proven wiped.
- Binaries use Apple/system frameworks. Private locking and deprecated Keychain APIs remain compatibility risks.

## Verification ledger

Passed before the candidate: v1.0.5 real lock/unlock/relock, but its display-asleep begin failed before typing. Earlier v1.0.4 passed immediate unlocks and failed a display-asleep attempt after input. These are separate outcomes, not proof of unattended reliability.

Candidate checks: compilation/signature, session and lease policy, focus/display readiness, request schema/framing, nested-modal dispatch, Apple loginwindow identity. See CI for portable checks. Local runtime and UI outcomes are recorded below after execution; no unperformed check counts as passed.

## Public release gates

1. Verify the exact release build on real awake and sleeping desktops, with repeated cycles, simultaneous leases, lease expiry, manual lock, helper crash/restart, modal setup and account switching. Preserve manual FileVault login.
2. Resolve or explicitly accept the focus/event-delivery race and enforcement-under-stall limitation after independent security review.
3. Establish stable signing/notarization and a safe upgrade/migration workflow; stop requiring unexplained repeated re-enrollment.
4. Select an open-source license after provenance review, including dependencies and generated assets. No upstream license or source reuse rights are assumed from a public GitHub page.
5. Set a private vulnerability-reporting channel, supported-version policy and reproducible release checks. Complete a final secret/privacy scan of the exact public tree and history.

Until those gates are satisfied, keep the repository private and do not publish a release or describe the app as security-certified.

## Local candidate outcomes

The installed 1.0.6 helper passed two `wake-check` calls starting with an actually sleeping display, with `password_attempted=false` and 21 awake samples. Malformed request and slow-client tests passed in the real socket service without changing task or credential state. The installer ran successfully and preserved a local backup. At the original review, full password unlock, timed modal expiry, crash recovery and native UI verification were pending. November 10 testing subsequently verified credential unlock, relock and native status-window access. Timed modal expiry and crash recovery remain unverified for this build.

The initial staged tree was checked for private-key/token patterns, personal machine paths and accidentally staged runtime/build artifacts. No matches were found. This scan is not proof that no secret could exist; only reviewed source, documentation, tests and generated assets were staged.

## Follow-up through November 11, 2026

See [the validation record](VALIDATION.md) for successful real unlocks and their limits. Display wake remains intermittent. On November 11, a successful unlock and Finder screenshot were followed by a missing-lease error during cleanup. Status showed an unlocked desktop and zero active tasks; explicit locking succeeded. The cause is unconfirmed. Investigate lease loss before claiming reliable unattended cleanup. No public-release gate is waived by these successful individual unlocks.
