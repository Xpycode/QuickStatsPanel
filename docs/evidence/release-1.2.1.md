# Release 1.2.1 preparation — 2026-11-12

Owner requested project status and release 1.2.1. Publication remains pending.

- Fresh universal Release archive and Developer ID export succeeded (version/build 1.2.1/1201). Both arm64 and x86_64 are present.
- Strict app and nested Sparkle signature verification passed with access to macOS signing services. Sandboxed verification failed; the unsandboxed verification returned exit 0.
- Logs and candidate: `04_Exports/release-1.2.1/`; exported app: `04_Exports/release-1.2.1/export/QuickStatsPanel.app`.
- Existing focused tests and paired-display/manual no-update acceptance are retained; no new tests or interactive acceptance ran.
- Owner confirmed Strongbox backup is **not yet complete**.
- Owner explicitly authorized Apple notarization after the initial automatic approval rejection. The file-based setup lacked its issuer setting; the documented `quickstatspanel-notary` Keychain profile succeeded.
- Apple accepted the app (`ef2996a9-8f3e-43cd-a7ff-0bbc232617cd`) and DMG (`5ea52b3b-888b-4250-9078-5193fde41025`). Both stapling validations and Gatekeeper assessments passed; packaging exited 0.
- `feed-candidate/appcast.xml` and its DMG enclosure were signed and verified with the dedicated Sparkle key. The read-only mounted DMG matched the exported app; nested signatures passed and the mount was detached. Feed preparation exited 0. Version/build 1.2.1/1201, minimum macOS 15.0.0 and enclosure URL reviewed.
- Artifact: `04_Exports/release-1.2.1/QuickStatsPanel-1.2.1-1201.dmg`. Hashes and source commit are in `04_Exports/release-1.2.1/receipt.json`; logs are `package-keychain.log` and `appcast.log` in that directory.
- No publication, installed-app replacement or app launch occurred. Live feed remains unchanged.
- Remaining: Strongbox backup; updater-control acceptance; actual upgrade/relaunch with retained preferences/history; publication and HTTPS byte verification.

Existing AGENTS.md, CLAUDE.md and output/ changes were preserved.
