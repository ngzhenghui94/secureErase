# Secure Erase

A small macOS app for best-effort overwriting and deleting selected files and folders through drag and drop.

> **Not a guarantee of permanent erasure.** SSD wear levelling and APFS copy-on-write can leave old data behind. Snapshots, backups, other copies and filename history may survive. FileVault protects a volume; deleting an individual file does **not** perform per-file cryptographic erasure. Use this app only when these limitations are acceptable.

Regular files have their data fork and any non-empty resource fork overwritten with random bytes, flushed, and logically read back for verification before truncation and deletion. **Flushed logical readback cannot prove physical-media sanitization.**

## Requirements

- macOS 14 or later.
- Xcode Command Line Tools (including the Swift compiler). Install them with `xcode-select --install` if needed, then complete Apple's installer.

## Build and install

```sh
git clone https://github.com/ngzhenghui94/secureErase.git
cd secureErase
sh build.sh
```

The build creates `SecureErase.app`, generates its icon, applies an ad-hoc code signature, and runs the built-in self-test. A successful test prints `selftest ok`.

In Finder, open the repository folder and drag the generated **SecureErase.app** into **Applications**. For an update, quit the old app first, then replace the existing copy in Applications. Launch it by double-clicking **SecureErase.app** in Applications.

This self-built app is ad-hoc signed, not Developer ID signed or notarized by Apple. macOS may apply security checks or block opening it; keep OS protections enabled and review any warning before proceeding.

## Use

**Try disposable data only before using the app on anything important. Deletion bypasses Trash and cannot be undone.**

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
