# Fork preparation

Source candidate based on pluk-inc/markdown-preview main at be03f33, with the existing fork's iOS/iPad app, searchable recents, document editing/undo, and table helpers retained. The macOS application uses the current upstream architecture; rendered table edits are integrated with its conflict-aware save path. iOS deliberately retains its compatible renderer under ios-preview/Rendering; it does not automatically gain all new macOS rendering features.

This is a review candidate, not a tested binary release. See [the review notes](docs/fork-review.md) for validation results and known gaps.

## Build

Copy Developer.local.xcconfig.example to the ignored Developer.local.xcconfig only if signing is needed. Configure your own bundle identifiers and app groups before distributing a signed fork. Run `swift test --package-path tests/swift-tests` for helper and WebKit tests. Build the `md-preview` and `Markdown Preview iOS` schemes in Xcode.

## Distribution

Automatic update checks are disabled and the upstream feed URL, Sparkle public key, Sentry DSN, and analytics token are absent from the app plist. The Sentry SDK dependency is excluded; crash-reporting controls remain off until it is explicitly restored. Inherited release/rollback scripts stop immediately. Configure and review fork-owned infrastructure before enabling distribution. Upstream website, donation, support and release-note links still refer to upstream; rebranding those is a release decision.

## Provenance

The original local repository and all history remain intact outside this candidate. This sanitized source tree is prepared for a separate review branch in the existing GitHub fork. The GitHub review branch retains the existing public fork and upstream histories, but excludes the separately rewritten private local history. Preserve LICENSE, upstream CHANGELOG, third-party licenses, and contributor credit. No release version has been assigned to this fork.
