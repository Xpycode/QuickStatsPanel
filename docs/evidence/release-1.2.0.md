# Release 1.2.0 — 2026-10-28

Owner requested publishing the current implementation and evaluating issues during ordinary use.
Remaining manual acceptance is explicitly deferred, not passed. No extra feature work was added.

| Bucket | Finding | Disposition |
|---|---|---|
| Ship blocker | No demonstrated new crash, data loss or security blocker found in reviewed changes | 113/113 Release hostless tests, fresh universal archive/export, strict signatures, app/DMG notarization, staple and Gatekeeper checks passed |
| Required distribution | Actual packaged and deployed bytes | Read-only mounted DMG app matches export executable; enclosed signature/Gatekeeper passed; GitHub DMG/ZIP and website download match local bytes; page/catalogue match uploaded bytes |
| Deferred validation | Remaining broader card checks, storage hardware status, clean-Mac and full release-artifact interaction acceptance | Owner explicitly deferred to everyday use; not claimed as tested |
| Existing follow-up | No automatic updater; established optional backlog and Help/citizenship refinements | No scope expansion for this release; manual download remains the distribution method |

113/113 automated checks passed · 0 demonstrated ship blockers · remaining manual checks explicitly deferred by owner.
The exact notarized Release app launched and remained running at the post-package process check.
No click/keyboard, clean-profile replacement or installation into Applications was performed.
See [machine-readable receipt](release-1.2.0.json) and [session](../sessions/2026-10-28.md).
Build/test/package/handoff logs and original website backups are in ignored `04_Exports/release-1.2.0/`.
