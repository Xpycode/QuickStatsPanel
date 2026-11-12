# Sparkle updates

## App behavior

QuickStatsPanel 1.2.1 integrates Sparkle 2.10.0, pinned in `01_Project/project.yml`.
One `UpdaterController` owns the standard Sparkle updater, started after application launch.
The strip context menu and Settings → About offer Check for Updates. About also exposes
Sparkle's own persisted automatic-check preference; it is off by default and Reset to Defaults
turns it off. Installation always requires user confirmation. System profiling is disabled.
Manual checks hide the floating strip so it cannot cover Sparkle's dialog. The existing
application termination path flushes retained transfers before replying to termination.
No Dock icon or menu-bar item is introduced.

Feed: https://apps.lucesumbrarum.com/quickstatspanel/appcast.xml

The feed and update archive must be signed. `SURequireSignedFeed` and
`SUVerifyUpdateBeforeExtraction` are enabled. The initial signed feed in
`distribution/appcast.xml` has no release entries; it must not advertise the development build.
Initial empty feed published and HTTPS bytes/signature verified on 2026-11-11.
1.2.0 has no updater: its first upgrade to a Sparkle-equipped release is manual.

## Signing key

Dedicated login Keychain account: `quickstatspanel`.
Public key: `zzrD5fCPunHZMbJiZzLSl80Amr/Wne1ybl4DHN+F1Rc=`.
Only this public key belongs in source control. Signing tools access the private key directly
through Keychain; do not retrieve private values into chat, command arguments or logs.
Custody is tracked in `/Users/sim/ProgrammingProjects/1-macOS/SPARKLE-KEY-REGISTRY.md`.
The user approved a protected mode-600 backup at
`/Users/sim/ProgrammingProjects/99-AUTH/quickstatspanel-sparkle-private.key`.
Strongbox backup remains an owner action; do not claim it completed.

Resolved tools for this integration:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/SparklePackages/artifacts/sparkle/Sparkle/bin`.
On another Mac resolve the pinned dependency and use that build's tools. Do not create a
replacement signing key if the existing account is missing; restore the same key securely.

## Release preparation

1. Build a universal Release archive and export using `scripts/exportOptions.plist`.
   Archive/export is responsible for Developer ID signing of Sparkle and nested helpers.
2. Run `scripts/package-dmg.sh VERSION APP_PATH`. The script verifies signatures instead of
   repairing them, notarizes and staples, and requires Gatekeeper acceptance. Outputs include
   version and build; existing artifacts must not be overwritten.
3. Run `scripts/make-appcast.sh APP_PATH DMG_PATH SPARKLE_BIN OUTPUT_DIRECTORY` with a new
   output directory. It validates the exact enclosed app against the supplied export and
   signs/verifies the archive and XML with account `quickstatspanel`.
4. Review the staged XML and release artifact. Upload the immutable DMG to the enclosure URL,
   verify HTTPS bytes and signature, then atomically publish the signed appcast. Never edit
   XML after signing. Preserve previous downloads and the published feed for rollback.
5. Download the published feed and artifact and verify exact hashes and Ed25519 signatures.
   Test an actual upgrade from a Sparkle-equipped installed build with retained preferences
   and transfer history. A no-update check does not prove replacement/relaunch.

Publishing a release and replacing the installed app are separate from preparing these files.
The initial empty feed is the only feed prepared by this integration before release packaging.

## Validation boundaries

The existing metric test target is hostless and does not compile the updater or app entry point;
its disposable-preference tests do not launch Sparkle or register hotkeys. Updater startup and
live UI validation require the actual app. Automatic checks remain disabled unless the owner
selects the checkbox. Do not change live preferences or install an update merely to run tests.

Sources: [Sparkle setup](https://sparkle-project.org/documentation/),
[programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/),
[configuration](https://sparkle-project.org/documentation/customization/),
[archive/export signing](https://sparkle-project.org/documentation/sandboxing/).
