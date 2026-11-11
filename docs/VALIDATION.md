# Beta validation record

This is a summary of observed development-machine results, not a supported-hardware matrix or an independent security audit. The current version is 1.0.6. Raw machine diagnostics and screenshots stay outside the repository.

## November 10, 2026

After refreshing the exact installed app's Accessibility permission and completing local password setup:

- A real `test-cycle` locked, unlocked and relocked the desktop.
- A separate `begin` started with `locked=true` and `display_awake=false`, returned `unlocked=true`, and allowed native app access.
- Ending that task lease returned the desktop to `locked=true`, with zero active tasks and no failed-attempt latch.

A later repeat first failed at `display_wake_timeout` before password input. A subsequent wake-only check passed, and another `begin` unlocked successfully. Native Calculator access and the result of a calculation were verified. Ending the lease relocked the desktop. This repeat establishes intermittent wake behavior, not a resolved regression.

## November 11, 2026

A task began with the desktop locked and the display asleep. `begin --seconds 900` returned `ok=true` and `unlocked=true`. Finder desktop access and a fresh screenshot were verified.

Cleanup then returned `Lease is missing or expired`. Status showed zero active tasks and an unlocked desktop. An explicit `lock` succeeded, and a second status read confirmed `locked=true`. The cause of the missing lease was not established. This task verifies successful unlocking and explicit locking, but does not verify normal lease-driven cleanup.

## Still unverified or unresolved

- Reliable repeated wake/unlock cycles in the intended headless display configuration.
- The cause of the November 11 missing-lease result.
- Full 1.0.6 coverage of concurrent tasks, lease expiry, manual lock revocation, modal setup expiry, helper crash/restart and account switching.
- Other Mac models, Intel hardware and other macOS versions.
- Remaining security, signing, licensing and public-release gates in the [audit](SECURITY-AUDIT.md).

Initial login after a cold boot or restart remains manual by design.
