# History and privacy review

The audit covered historical content, not only the candidate files. The original repository's complete object inventory contained 2,646 objects. Reachable and original-only commit, tag and blob contents were scanned, with original-only objects checked separately when absent from the isolated clone. The fetched public upstream/fork history, candidate working files, and newly uploaded review objects were also scanned. Ignored original working files were inspected but were not copied or uploaded.

No private-key or recognized common provider-token pattern matched. This is a heuristic scan, not a guarantee that an arbitrary secret, binary attachment or personal detail cannot remain. Historical screenshots were not exhaustively OCR-reviewed. The custom app icon was visually inspected, and PNG metadata was removed from the candidate tree.

## What the branch excludes

New review commits use a neutral contributor identity. They exclude the separately rewritten private local history, local signing configuration, Xcode user state, private raw logs, local agent configuration and local filesystem paths. Current source signing settings use a placeholder/local override, and configured telemetry/update credentials are absent. Generic example paths and third-party license/support contacts remain intentionally.

## What remains in existing public history

The repository was already public. Its existing fork history and public upstream ancestry are preserved. They can still expose author/committer names and email addresses, historical developer signing identifiers, historical file contents and asset metadata even when the current tree is sanitized. A new branch, a squash merge, or deleting a current file does not erase those objects.

No history rewrite, force push, visibility change or deletion was performed. The original local repository and history remain intact. This review branch does not claim to retroactively sanitize existing public history.

Before wider distribution, review whether retaining that attribution and historical personal metadata is acceptable. If removal is required, it needs a separately approved history-remediation plan or a new repository with intentionally limited history; that action is outside this review branch's authorization. Any actually discovered credential would additionally require rotation, because Git history removal alone would not make an exposed credential safe.
