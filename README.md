# Mac Session Helper

<img src="assets/AppIcon.png" width="112" alt="Mac Session Helper icon">

Temporary desktop access for an automation running in an already logged-in macOS account. A local client requests a lease of 30 to 900 seconds. The helper uses a password stored in the login Keychain, verifies the secure Apple loginwindow target, and relocks a desktop it unlocked when its last lease ends.

**Experimental. Not ready for public release or unattended reliance.** Immediate unlock tests have passed on macOS 27.2, but sleep/wake regressions prompted further changes. The current 1.0.6 build still needs full live credential-unlock and relock verification. See [the audit](docs/SECURITY-AUDIT.md) for findings and release gates.

## Boundaries

- Initial login after shutdown or restart is manual. This is not a FileVault unlock service.
- No automatic login, system daemon, network listener, telemetry or updater is installed.
- The CLI never accepts or returns a password. Enrollment happens in the app's secure field.
- A failed password attempt blocks further attempts until successful local enrollment. Never delete the latch to retry.
- Any process running as the same user can request access. This does not protect against malware running as that account.

Read [SECURITY.md](SECURITY.md) before using the helper. Focus checks and synthetic keyboard input are not atomic, and Swift cannot guarantee that every transient password copy is wiped from memory.

## Build and install

Requires macOS, Xcode Command Line Tools and Python 3. Run as the logged-in user, without sudo:

```sh
zsh test.sh
zsh install.sh
```

The app installs at `~/Applications/Mac Session Helper.app`, the client at `~/.local/bin/mac-session`, and an Aqua LaunchAgent at `~/Library/LaunchAgents/local.mads.MacSessionHelper.plist`. The legacy bundle identifier remains `local.mads.MacSessionHelper` to preserve existing installations; it is not a credential.

The default build is ad-hoc signed. A rebuild may require removing and re-adding the installed app in Privacy & Security → Device Control and Data Access, plus local password enrollment. On older macOS versions this permission is named Accessibility. For development with an existing code-signing identity, set `SIGNING_IDENTITY` when building. No signing certificate or private key is bundled.

Open the app for its status window. Choose Password setup, enter the Mac login password locally, and dismiss the success message. Then run `mac-session test-cycle` while unlocked and with no other desktop tasks. That explicit test ends locked. A build passing unit tests is not proof of successful desktop unlocking.

## Task use

```sh
mac-session status
mac-session begin --seconds 900
mac-session renew LEASE_FROM_BEGIN --seconds 900
mac-session end LEASE_FROM_BEGIN
```

Save the returned lease. Renew only while actively working and end before waiting for a user or finishing. Each concurrent task needs its own lease. Ending the last lease locks only a desktop the helper unlocked. A manual lock revokes leases; renewal cannot unlock again.

`mac-session pause` disables unlocking and locks. Resume from the local menu. `mac-session lock` locks immediately. `mac-session setup` explicitly opens local enrollment. `mac-session wake-check` only requests and checks display wake; it does not retrieve or type the password, unlock the session, or clear the failure latch.

The helper also has a 15-minute idle lock. It leaves native energy and password-grace settings unchanged. Leases are never restored after a restart. A same-session recovery marker allows a restarted helper to relock a desktop it previously unlocked.

## Testing

`test.sh` runs session/lease policy, protocol validation, stable-focus/display-readiness, modal-loop and trusted-process tests. The signature test checks the system loginwindow when available. `zsh test.sh --live-display` additionally sleeps and wakes the actual display without reading or typing a credential. Do not run it during someone else's desktop task.

`Tests/runtime_protocol.py` checks only malformed requests and status against an installed helper; it never requests unlocking. `Tests/protocol_test.py` is an older pre-enrollment test and refuses to run after enrollment.

Full release verification must also cover real awake and display-asleep unlocks, concurrent leases, expiry, manual lock revocation, crash recovery, local setup failures and account/session changes. Cold boot remains manual.

## Removal and recovery

Run `mac-session pause` first, then unload the user LaunchAgent. Move the installed app, client and LaunchAgent to Trash. Runtime files live under `~/Library/Application Support/MacSessionHelper`. Installer backups live under `~/Library/Application Support/MacSessionHelperBackups` and are never committed.

If desired, remove only the `Mac Session Helper (local session only)` item in Keychain Access. Never delete the login Keychain or unrelated items. The installer does not modify TCC permissions, FileVault or credentials.

## Provenance and release status

The approach was informed by [BLEUnlock](https://github.com/ts1/BLEUnlock), but this is a separate implementation with task leases and additional target checks. No upstream source file is vendored. It uses Apple's private lock API and deprecated Keychain ACL APIs, so compatibility is not guaranteed across macOS versions.

The icon was generated with OpenAI's image tool; its prompt is in [assets/PROVENANCE.md](assets/PROVENANCE.md). No open-source license has been selected yet. Keep this repository private until licensing, audit follow-up and the live validation gates are complete. No public release assets have been published.
