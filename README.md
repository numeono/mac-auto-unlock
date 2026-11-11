# Mac Session Helper

<img src="assets/AppIcon.png" width="112" alt="Mac Session Helper icon">

Mac Session Helper is built primarily for **headless Mac mini setups** that run desktop automation. It gives a local automation temporary access to an already logged-in macOS desktop, then relocks a desktop it unlocked when the last task lease ends. A lease lasts 30 to 900 seconds. The helper stores the login password in the local login Keychain and checks the secure Apple loginwindow target before typing it.

For example, an agent on a Mac mini can request desktop access, use a native app, and release access when finished. Shell jobs that do not need the desktop should run while it stays locked. The helper provides session access; it does not provide remote desktop viewing or control.

**Beta. Version 1.0.6 is still experimental and not ready for unattended reliance.** Real lock/unlock/relock and sleeping-display unlock tests have passed on the development Mac mini. Wake failures remain intermittent. A later successful unlock also lost its task lease before cleanup and needed an explicit lock. See the [validation record](docs/VALIDATION.md) for dated results and [the audit](docs/SECURITY-AUDIT.md) for remaining release gates.

## Boundaries

- Initial login after shutdown or restart is manual. This is not a FileVault unlock service.
- No automatic login, system daemon, network listener, telemetry or updater is installed.
- The CLI never accepts or returns a password. Enrollment happens in the app's secure field.
- A failed password attempt blocks further attempts until successful local enrollment. Never delete the latch to retry.
- Any process running as the same user can request access. This does not protect against malware running as that account.

Read [SECURITY.md](SECURITY.md) before using the helper. Focus checks and synthetic keyboard input are not atomic, and Swift cannot guarantee that every transient password copy is wiped from memory.

## Headless setup requirements

Headless means normal operation without a directly attached keyboard or monitor. It does not mean the Mac can boot into an unattended authenticated session. You must complete the initial login after every shutdown or restart. Arrange a way to reach the Mac for that login and for permission or credential recovery before relying on remote automation.

The helper runs in the account's existing graphical session through an Aqua LaunchAgent. An SSH connection alone does not create that session. The desktop must remain available to macOS, and the helper must be able to wake it and verify the login field. Operation with every monitor, display adapter and remote-access configuration has not been verified.

The app declares macOS 14.0 as its minimum. Live testing so far covers an Apple Silicon Mac mini on macOS 27.2, not a compatibility matrix. Intel Macs and other macOS versions are unverified. FileVault and manual initial login stay enabled.

## Build and install

You need Git, Xcode Command Line Tools with the macOS SDK and Swift compiler, and Python 3. The installer also uses `/usr/bin/python3`. There is no packaged or notarized download. While the repository is private, cloning requires access granted by the owner.

Run as the logged-in user, without sudo:

```sh
git clone https://github.com/numeono/mac-session-helper.git
cd mac-session-helper
zsh test.sh
zsh install.sh
export PATH="$HOME/.local/bin:$PATH"
mac-session status
```

Add `~/.local/bin` to your shell's PATH if needed, or invoke `~/.local/bin/mac-session` directly. Installation starts the helper for the current graphical session and registers it to start at future logins.

The app installs at `~/Applications/Mac Session Helper.app`, the client at `~/.local/bin/mac-session`, and an Aqua LaunchAgent at `~/Library/LaunchAgents/local.mads.MacSessionHelper.plist`. The legacy bundle identifier remains `local.mads.MacSessionHelper` to preserve existing installations; it is not a credential.

The default build is ad-hoc signed. A rebuild may require removing and re-adding the installed app in Privacy & Security → Device Control and Data Access, plus local password enrollment. On older macOS versions this permission is named Accessibility. For development with an existing code-signing identity, set `SIGNING_IDENTITY` when building. No signing certificate or private key is bundled.

For first-time setup:

1. Open `~/Applications/Mac Session Helper.app`. Grant that exact installed app Device Control and Data Access, or Accessibility on older macOS versions.
2. Choose Password setup in its status window. Enter the Mac login password locally and dismiss the success message. Never put the password in a command, script, issue or agent conversation.
3. Check `mac-session status`. Confirm `accessibility`, `credential_saved`, `eligible_session` and `enabled` are true, and `attempt_blocked` is false. `credential_saved` only proves that an entry exists; it does not prove the current app can read it.
4. While unlocked and with no other desktop tasks, run `mac-session test-cycle`. This deliberately locks, unlocks and relocks the desktop. Have a recovery path ready.
5. Test a separate task from a locked desktop and verify actual app access, lease release and the final locked state. Also test your normal display-sleep condition before using the helper remotely.

A build passing unit tests is not proof of successful desktop unlocking. See [troubleshooting](docs/TROUBLESHOOTING.md) if setup or a live test fails.

## Task use

```sh
mac-session status
mac-session begin --seconds 900
mac-session renew LEASE_FROM_BEGIN --seconds 900
mac-session end LEASE_FROM_BEGIN
```

Each command returns JSON and exits nonzero on failure. Check `ok` before continuing. In a successful `begin` response, `unlocked` means the desktop was locked when the request began; it is false when the desktop was already unlocked. Save the returned lease. Renew only while actively working and end before waiting for a user or finishing.

Each concurrent task needs its own lease. Ending the last lease locks only a desktop the helper unlocked. A manual lock revokes leases; renewal cannot unlock again.

Put lease release in your task's cleanup path and read `status` afterward. When the helper unlocked the desktop and no other task remains, verify `locked=true` and `active_tasks=0`. A missing-lease error does not prove that the desktop is locked. See [troubleshooting](docs/TROUBLESHOOTING.md) for recovery without interrupting other work.

`mac-session pause` disables unlocking and locks. Resume from the local menu. `mac-session lock` locks immediately. `mac-session setup` explicitly opens local enrollment. `mac-session wake-check` only requests and checks display wake; it does not retrieve or type the password, unlock the session, or clear the failure latch.

The helper also has a 15-minute idle lock. It leaves native energy and password-grace settings unchanged. Leases are never restored after a restart. A same-session recovery marker allows a restarted helper to relock a desktop it previously unlocked.

## Testing

`test.sh` runs session/lease policy, protocol validation, stable-focus/display-readiness, modal-loop and trusted-process tests. The signature test checks the system loginwindow when available. `zsh test.sh --live-display` additionally sleeps and wakes the actual display without reading or typing a credential. Do not run it during someone else's desktop task.

`Tests/runtime_protocol.py` checks only malformed requests and status against an installed helper; it never requests unlocking. `Tests/protocol_test.py` is an older pre-enrollment test and refuses to run after enrollment.

Full release verification must also cover real awake and display-asleep unlocks, concurrent leases, expiry, manual lock revocation, crash recovery, local setup failures and account/session changes. Cold boot remains manual.

## Removal and recovery

Run `mac-session pause` first, then unload the user LaunchAgent:

```sh
launchctl bootout "gui/$(id -u)/local.mads.MacSessionHelper"
```

Move the installed app, client and LaunchAgent to Trash. Runtime files live under `~/Library/Application Support/MacSessionHelper`. Installer backups live under `~/Library/Application Support/MacSessionHelperBackups` and are never committed.

If desired, remove only the `Mac Session Helper (local session only)` item in Keychain Access. Never delete the login Keychain or unrelated items. The installer does not modify TCC permissions, FileVault or credentials.

## Provenance and release status

The approach was informed by [BLEUnlock](https://github.com/ts1/BLEUnlock), but this is a separate implementation with task leases and additional target checks. No upstream source file is vendored. It uses Apple's private lock API and deprecated Keychain ACL APIs, so compatibility is not guaranteed across macOS versions.

The icon was generated with OpenAI's image tool; its prompt is in [assets/PROVENANCE.md](assets/PROVENANCE.md). No open-source license has been selected yet. Keep this repository private until licensing, audit follow-up and the live validation gates are complete. No public release assets have been published.

## Contributions and bug reports

See [CONTRIBUTING.md](CONTRIBUTING.md) for development checks and the details to include in a bug report. The repository is currently private and has no open-source license. These instructions are for authorized testers; public distribution is still pending.
