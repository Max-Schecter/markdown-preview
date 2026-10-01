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
- Math/Mermaid smoke checks passed.
- Editor-transition/zoom and checkbox save/conflict probes passed in the reconciliation copy. Candidate reruns use a fresh absolute compiler-cache path because reusing one cache through two relative paths exposed an Xcode beta compiler-cache collision.
- The full Swift suite compiled, but the run was stopped after 136 observed passing test cases and seven failing editor-formatting test cases. The editor Swift source, bundled editor JavaScript and affected test file are unchanged from upstream. A pristine-upstream baseline is still required to attribute the failures conclusively.
- Xcode project and plist syntax checks passed. Unsigned macOS/Quick Look and generic iOS Simulator builds are being validated; final results will be recorded below.
- No app was installed or launched for interactive testing. No simulator was booted or used. Signing, notarization, publishing and updater services were not exercised.

Failing WebKit cases observed in `EditorFormattingTests`: missing table cells, formatting after blur, table click anchoring, formatting with pipes/whitespace/Unicode/empty cells, stale targets after document replacement, table link/keyboard formatting, and native pointer selection.

## Security and privacy review

All 2,646 objects from the original repository were covered by redacted object scans, including original-only objects absent from a normal clone. Working-tree scanning included ignored local files. No private-key or recognized provider-token pattern matched. Historical author emails/signing identifiers and ignored local machine paths were identified. Private local history, ignored files and raw audit/build logs are not included in this branch.

The current candidate was scanned separately. Remaining heuristic matches are public license/support contacts, generic `/Users/me` test/example paths, placeholder signing configuration, renderer token/sentinel code, vendor code, a non-secret analytics service URL, and binary/asset-name false positives. The app has no configured analytics token. This is a heuristic audit, not a proof that all possible sensitive information is absent.

The existing GitHub fork is already public. This branch does not erase or rewrite its existing public history, change repository visibility, replace its default branch or publish a binary release.

## Before merge or binary distribution

Resolve or establish the baseline for the WebKit failures. Verify rendered table typing/focus, row/column operations, undo/redo, external-file conflicts and transitions between read/edit modes. Exercise iOS file opening, security-scoped persistence, searchable recents and appearance. Verify Quick Look in its real host.

Choose fork-owned bundle identifiers/app groups, branding/support links and a version before signing or distributing. Upstream links and identifiers remain where explicitly documented in `FORK.md`. Re-enable distribution scripts and service integrations only after configuring and reviewing fork-owned infrastructure.
