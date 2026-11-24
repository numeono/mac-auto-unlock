# Setup and recovery

Start with `mac-session status`. After a reboot, the helper resumes when macOS brings back your desktop session. If macOS pauses at FileVault or asks you to sign in, complete that step first.

| Symptom | Next step |
| --- | --- |
| Cannot connect to the helper | Confirm the account has completed its graphical login. Check `launchctl print "gui/$(id -u)/local.mads.MacSessionHelper"`. The installed app and LaunchAgent must belong to that account. |
| `eligible_session=false` | Return to the intended logged-in console account. SSH access alone is insufficient. Do not bypass the session check. |
| `accessibility=false` | Grant the exact installed `~/Applications/Mac Session Helper.app` its permission. After a rebuild, an enabled-looking stale entry may need removal and re-addition. Complete any macOS authentication yourself, then check runtime status again. |
| `credential_saved=true`, but the credential cannot be read | Open Password setup locally and enroll again. A saved entry can belong to an older signing identity. Never export or retrieve the password through a script. |
| `attempt_blocked=true` | Unlock manually and complete successful local Password setup. Do not delete the latch, repeatedly retry the password, or disable target verification. |
| Display wake fails before password input | Run `mac-session wake-check` to test wake without reading or typing the password. Wake remains intermittent in 1.0.6. If it still fails, recover the desktop manually. Do not build an unlimited retry loop. |
| Secure login field cannot be verified | Stop and unlock manually. Do not substitute coordinates or type into an unverified window. |
| `setup_open=true` | Finish or dismiss local setup before starting a task. |
| `enabled=false` | Resume from the helper's local menu if you intend to enable task access. |
| Lease is missing or expired | Read status and stop using the revoked lease. Manual locking, expiry or a helper restart can invalidate leases. Do not assume the desktop relocked. If this was your exclusive task, the desktop is unlocked, and `active_tasks=0`, use `mac-session lock` and verify `locked=true`. Do not lock over another person's or task's work. |

## Updating a development installation

Finish all active desktop tasks and close Password setup. Review the incoming changes, run `git pull --ff-only`, then `zsh test.sh` and `zsh install.sh`. The installer creates a local backup of an existing app and LaunchAgent under `~/Library/Application Support/MacSessionHelperBackups`.

Ad-hoc signing can change the app's identity after a rebuild. Recheck Accessibility and credential access, then repeat live tests. A successful installation alone does not establish working unlocks. Do not rebuild a working installation merely to inspect its status.

## Useful diagnostics

For a bug report, include the helper version, macOS version, Mac model, whether a display was connected or asleep, the command name, its sanitized response and the final locked state. State whether another person, task or remote session was active. Include the exact order of events.

Runtime diagnostics live under `~/Library/Application Support/MacSessionHelper`. The helper writes stage information to `last-unlock.json`, `last-wake.json` and `last-setup.json`. Inspect and redact relevant fields before reporting them. Do not upload the whole runtime directory, raw authentication logs, passwords, Keychain exports or screenshots with unrelated private information.

Report security findings through the private channel described in [SECURITY.md](../SECURITY.md).
