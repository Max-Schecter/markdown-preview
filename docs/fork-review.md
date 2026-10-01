# Upstream reconciliation and source sanitization

This review branch updates the fork to upstream main `be03f333141af032c9a18220712c763c6cf30d25`. It retains the existing GitHub fork and upstream histories. It does not include the separately rewritten local fork history. The original working repository and all original files remain unchanged.

## Changes

- Adopt upstream's reorganized macOS app, renderer, editor, settings and document architecture.
- Preserve the fork's iOS/iPad app, searchable recents, app icon, document editing, appearance controls, table/task editing and undo/redo helpers. iOS retains a compatible renderer under `ios-preview/Rendering`; new macOS features do not automatically propagate to iOS.
- Connect macOS rendered table edits to upstream's conflict-aware persistence and register undo operations. Migrate the previous preview appearance preference to upstream's shared preference.
- Keep developer signing in an ignored local configuration. Exclude local Xcode state, agent settings, private signing files and local notes.
- Remove configured telemetry/update credentials from the application plist, disable automatic upstream update checks, and omit the unconfigured Sentry dependency. Inherited distribution scripts stop before performing any action.
- Remove PNG metadata and source header author metadata while retaining upstream licensing, third-party notices and public contributor attribution.
- Correct static renderer checks for upstream's new file locations and popup message shape.

## Validation

- 57 retained helper tests passed, including table/task source transformations and undo/redo history.
- 64 rendering regression tests passed after updating the table-editing contract assertions.
- Math/Mermaid smoke checks passed.
- Editor-transition/zoom and checkbox save/conflict probes passed in the sanitized candidate using a fresh absolute compiler-cache path.
- The initial seven editor-formatting failures reproduced on pristine upstream. An unordered, invisible, non-key window in the test harness restores native WebKit focus/blur delivery without activating the application. All 25 upstream formatting tests passed with this harness; all 26 candidate formatting tests, including a new focus regression, passed.
- The completed candidate run executed 455 tests, with one skipped and nine failed assertions in one case: the inherited read-only table contract. That run preceded the table capability fix below; it is not a clean full-suite result.
- Table mutation now requires an explicit main-app capability as well as a host bridge. Generic preview hosts and Quick Look remain read-only. Eight lightweight DOM capability combinations passed. New native regression coverage includes initial, morphdom and fallback updates; it has not yet been run after this fix.
- 36 performance comparison/reporting unit tests passed. The initial performance CI failed because the old fork has no editor benchmark target. For that exact migration base only, the runner now compares against the reconciled upstream commit, verifies its ancestry, and records both requested and actual baselines. This measures fork overhead against upstream; no old-fork performance comparison is claimed. The actual benchmark remains pending.
- The editor bundle rebuilt byte-for-byte from its source. Its DOM smoke suite exposed an incomplete image-click gesture, now corrected. Other runs had varying syntax/render readiness failures under host contention; the complete DOM smoke suite is not verified green.
- Xcode project and plist syntax checks passed. The unsigned iOS/iPad build succeeded for generic iOS Simulator (arm64 and x86_64). The unsigned macOS Debug build, including Quick Look, also succeeded.
- No app was installed or launched for interactive testing. No simulator was booted or used. Signing, notarization, publishing and updater services were not exercised.

The final capability/test/benchmark follow-up has not received another native build or full test run. Heavy local checks were stopped after the completed run because other tasks reported severe host contention. GitHub CI on the follow-up is the next independent validation step.

## Security and privacy review

See [history-privacy.md](history-privacy.md) for audit coverage and the personal information retained in existing public history.

All 2,646 objects from the original repository were covered by redacted object scans, including original-only objects absent from a normal clone. Working-tree scanning included ignored local files. No private-key or recognized provider-token pattern matched. Historical author emails/signing identifiers and ignored local machine paths were identified. Private local history, ignored files and raw audit/build logs are not included in this branch.

The current candidate was scanned separately. Remaining heuristic matches are public license/support contacts, generic `/Users/me` test/example paths, placeholder signing configuration, renderer token/sentinel code, vendor code, a non-secret analytics service URL, and binary/asset-name false positives. The app has no configured analytics token. This is a heuristic audit, not a proof that all possible sensitive information is absent.

The existing GitHub fork is already public. This branch does not erase or rewrite its existing public history, change repository visibility, replace its default branch or publish a binary release.

## Before merge or binary distribution

Require a clean follow-up Swift CI run and inspect the performance results. Resolve the remaining DOM smoke failures or establish their isolated baseline. Verify rendered table typing/focus, row/column operations, undo/redo, external-file conflicts and transitions between read/edit modes. Exercise iOS file opening, security-scoped persistence, searchable recents and appearance. Verify Quick Look in its real host.

Choose fork-owned bundle identifiers/app groups, branding/support links and a version before signing or distributing. Upstream links and identifiers remain where explicitly documented in `FORK.md`. Re-enable distribution scripts and service integrations only after configuring and reviewing fork-owned infrastructure.
