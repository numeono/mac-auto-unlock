# Contributing

Mac Session Helper is an experimental alpha under the [MIT license](LICENSE).

## Development checks

Read [SECURITY.md](SECURITY.md) and [the audit](docs/SECURITY-AUDIT.md) before changing authentication, focus, session or lease behavior.

```sh
zsh test.sh
zsh build.sh
zsh -n build.sh install.sh test.sh
git diff --check
```

Building creates a local bundle under `build/`; it does not replace the installed app. Installation is a separate step and may require renewed permission and local password setup. CI builds and runs regression checks. It does not enroll a credential or prove a real desktop unlock.

Use `zsh test.sh --live-display` only on a machine where you can safely sleep the display. Real credential tests require local enrollment and a recovery path. Do not run display or locking tests during another person's desktop work.

For behavior changes, add a focused regression test where possible and describe the actual live checks performed. Keep failed and unperformed cases explicit. Preserve the failed-attempt latch, desktop session checks, secure-target checks and per-task leases.

## Reporting a problem

Open a GitHub issue for ordinary bugs. Include sanitized reproduction steps, expected and observed behavior, version and display setup. See [troubleshooting](docs/TROUBLESHOOTING.md) for useful diagnostics. Follow [SECURITY.md](SECURITY.md) for security findings.

Before committing, review `git diff --cached`. Never stage runtime data, credentials, signing keys, local artifacts or screenshots containing personal information. Keep generated builds and machine-specific files out of Git.
