# Secure Erase

A small macOS app for best-effort overwriting and deleting selected files and folders through drag and drop.

> **Not a guarantee of permanent erasure.** SSD wear levelling and APFS copy-on-write can leave old data behind. Snapshots, backups, other copies and filename history may survive. FileVault protects a volume; deleting an individual file does **not** perform per-file cryptographic erasure. Use this app only when these limitations are acceptable.

Regular files have their data fork and any non-empty resource fork overwritten with random bytes, flushed, and logically read back for verification before truncation and deletion. **Flushed logical readback cannot prove physical-media sanitization.**

## Requirements

- Apple Silicon (arm64), macOS 14 (Sonoma) or later.
- Xcode Command Line Tools (including the Swift compiler). Install them with `xcode-select --install` if needed, then complete Apple's installer.

## Build, release, and install

Run `./build.sh` from the maintained checkout. Every normal build assigns a new numeric version and increasing build number, builds with Sparkle 2.10.0, Developer ID signs with the existing team `F57QJC4XU3`, notarizes using Keychain profile `notary`, staples and validates Apple's ticket, checks code signatures and Gatekeeper, and publishes immutable release assets. Requires Xcode tools, Python 3, authenticated GitHub CLI push access, and the existing organization Sparkle signing key (Keychain account `local.swissKnife`). No signing keys are exported or Keychain permissions changed.

The final app stays at `SecureErase.app`; immutable apps and packages live under `build/releases/VERSION/`. Normal builds run erasure self-tests on their own disposable temporary fixtures, updater safety self-tests, and numeric release self-tests. They never install an app, erase user-selected files, grant permissions, or modify an installed copy. To install, quit the installed app and copy the final **SecureErase.app** into Applications when intended. Keep Gatekeeper and quarantine enabled.

### Secure in-app updates

Choose **Secure Erase → Check for Updates…**. Checks and downloads are manual only; no system profile is sent. The feed and ZIP have verified Ed25519 signatures; archive verification occurs before extraction, and the replacement must preserve `local.secureerase` and the publisher's Developer ID identity. Update checks are rejected while any window is erasing. Pending installation blocks new erasure and waits for every active operation before relaunch. Canceling or failing installation releases its own guard. Normal quitting during erasure also waits for operations to finish. Older builds without Sparkle need one manual installation of a notarized release.

### Homebrew publication

The release destination remains `ngzhenghui94/secureErase` at `vVERSION`, with `SecureErase-VERSION-arm64.zip` and signed `appcast.xml`. The workflow creates a draft, downloads and verifies all asset checksums, publishes it, verifies public HTTPS downloads, then pushes the matching cask and signed feed to `ngzhenghui94/homebrew-tap`. Only the app-local `build/update-tap` clone is changed; it fetches/rebases before normal push. No authored app source is copied to the tap. The feed is `https://raw.githubusercontent.com/ngzhenghui94/homebrew-tap/main/appcasts/secureerase.xml`.

Install published releases with:

```sh
brew tap ngzhenghui94/tap
brew install --cask ngzhenghui94/tap/secureerase
```

`./package.sh --local` packages the final app into `build/homebrew/local/`, with a checksummed local cask. Do not publish its file URL. `./package.sh --release` requires notarization, signs the archive/feed, and refuses to overwrite `build/releases/VERSION/package`; normal releases already perform this step. Neither packaging mode installs or publishes.

If a build fails, preserve `build/releases`, `notarization.json`, any Apple submission/GitHub draft, and `build/update-tap`. Inspect any unpushed tap commit before retrying. Never blindly resubmit an unknown Apple result, overwrite assets, or remove the build lock while its process is running. Interrupted attempts reserve their versions; subsequent builds advance past them.

## Use

**Try disposable data only before using the app on anything important. Deletion bypasses Trash and cannot be undone.**

The main window shows the drop area without a persistent warning banner. Erasure limitations remain in the confirmation dialog.

1. Drag files or folders from Finder into **Drop files or folders here**.
2. Review the queued items. **Clear** removes the queue without erasing files.
3. Click **Erase …**, read the warning, and confirm **Overwrite and Delete** only for the intended items.
4. Wait for processing and review the results at the bottom of the window. **Logically deleted** means the operation completed, not that all remnants or copies are gone. Errors describe a failure and warn that partial erasure may have occurred.

Folders are processed recursively, including hidden files. Symbolic links are removed without following or erasing their targets. Regular files with multiple hard links and special files are refused. The filesystem root, your home folder itself, and volume roots are also refused.

**Errors do not roll back changes.** A failed file may already have been partly overwritten or truncated; a failed folder may already have lost some children. Processing continues with the other queued top-level items. Inspect the error and any remaining files rather than assuming they are intact.

## Self-test

From the repository folder, rerun the built binary's self-test:

```sh
./SecureErase.app/Contents/MacOS/SecureErase --selftest
```

It creates and erases its own disposable temporary fixtures and prints `selftest ok` on success. This checks logical behavior, not physical sanitization. For manual app testing, use only disposable files and folders.
