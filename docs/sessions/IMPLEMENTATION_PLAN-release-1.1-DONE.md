# v1.1.0 release completion

## Goal and scope
Finish the existing v1.1.0 (1100) release, authorized on 2026-10-03. Preserve the
HUD behavior and existing preferences. Longer graph history and cumulative
network/disk totals belong to a later release; persistence requirements remain open.

## Acceptance criteria
- [x] Fresh universal Release built from recorded source; logic tests pass.
- [x] Exact signed artifact passes launch/upgrade and clean-preferences checks.
- [x] App and DMG notarized, stapled and accepted by Gatekeeper.
- [x] Tagged GitHub release contains verified assets; product download metadata updated.

## Schedule and ownership
Coordinator owns build outputs, Git, packaging, documentation and publication.
Build → artifact testing → packaging → publication is serial because every stage
consumes the preceding artifact. A fresh-context read-only release reviewer runs
independently; it does not edit source or share the build directory.

## Tasks
- [x] **R1 — Build and verify candidate.** Depends on: none. Owns:
  `04_Exports/release-1.1.0/`, generated Xcode project, validation evidence.
  Success: universal Release and five logic tests pass; stable Developer ID signature;
  review findings dispositioned. Validation: XcodeGen, xcodebuild test/archive/export,
  codesign strict verification, lipo, Info.plist inspection.
- [x] **R2 — Exact-artifact acceptance.** Depends on R1. Owns smoke-test evidence and
  temporary preference backup. External gate: GUI testing availability.
  Success: launch, hint, hotkeys, graphs, detail cards, Settings, dragging and preference
  preservation verified on the candidate; original preferences restored after clean test.
- [x] **R3 — Notarize and package.** Depends on R1; publication also requires R2.
  Owns final DMG/ZIP. External gate E1 below. Success: app and DMG notarization accepted,
  tickets stapled/validated, Gatekeeper accepts both, mounted DMG app matches candidate.
  Validation: package-dmg.sh, stapler validate, codesign, spctl, SHA-256 manifest.
- [x] **R4 — Publish and close.** Depends on R2/R3. Owns release notes, tag/release,
  product metadata and project records. Success: release assets publicly reachable and
  product links/version correct; repository and handoff synchronized.
  Validation: gh release view, downloaded asset checksums, product-page checks.

## External gates
- [x] **E1 — Apple developer agreement.** `notarytool history --keychain-profile Manifest`
  returned HTTP 403 on 2026-10-03: required agreement missing or expired. Account holder
  accepted the agreement; both subsequent submissions were accepted. Gate cleared.

## Execution log
| Task | Assignment/evidence | Remaining work |
|---|---|---|
| Preflight | Coordinator compared every dirty/untracked file to origin: all identical. Stashed backup and fast-forwarded nine commits to e8d5771. Installed app on this Mac is v1.0.0. Developer ID identity available. | Fresh build required; earlier /tmp artifact unavailable here. |
| Review | Fresh-context `release_audit` agent, read-only source/packaging review. | No demonstrated source blocker; packaging check enforced separately. |
| E1 | Apple HTTP 403; account holder notified. | Agreement acceptance and successful retry. |

| R1–R3 | Coordinator: Xcode 27 universal Release, 5/5 tests, strict signature and both notarizations passed. Mounted DMG executable matches candidate SHA-256. Reviewer found no demonstrated source blocker. | R4 ready. |
| R2 | All 14 existing preferences preserved; clean first-run hint verified; CPU detail, Escape and physical-key summon passed. User approved installed notarized build with “Looks good—publish.” | Acceptance complete. |

| R3 | Both Apple submissions accepted after agreement acceptance. App/DMG staples and independent Gatekeeper checks passed. | Complete. |
| R4 | Published v1.1.0 on GitHub and updated website DMG/page/catalogue. Downloaded both GitHub assets and website DMG; all SHA-256 values match originals. | Complete; release evidence in 2026-10-03 session log. |

## Outcome
Plan complete. Application source is unchanged from e8d5771; release tag v1.1.0
points to ddbc76a (release-note date and temperature terminology only).
