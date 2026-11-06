# Security

VEIL is a development preview without an independent security review or a supported-release guarantee.

## Reporting

Use GitHub private vulnerability reporting if the repository's Security tab offers it. Otherwise open an issue requesting a private channel, without exploit details, credentials, personal browsing data or profile attachments. No response-time guarantee is established.

Revoke or rotate any exposed live key immediately. Deleting a file does not revoke credentials or establish removal from old Git objects, forks, caches or clones.

## Runtime boundaries

- Chromium's renderer sandbox is enabled. VEIL does not configure certificate-error bypass or disable web security.
- Page-to-native messages carry bounded lifecycle/media hints. No native filesystem, shell, cookie or Keychain commands are exposed. Pages can influence their own hints; these hints are not a trusted security attestation.
- Camera, microphone and recognized site permissions require prompts. Unknown permission categories are denied.
- CEF website storage uses a VEIL-specific Keychain service. Keychain names and bundle identifiers in source are public identifiers, not encryption keys.
- Workspace metadata, recovery snapshots and download paths are local plaintext. Profile directories are owner-only; this is not an encrypted vault or protection against the same user/administrator.
- Spaces share cookies. Private windows use an ephemeral shared context reset after the last private browser closes. Saved downloads persist. Private mode does not provide network anonymity.
- Local builds are ad-hoc signed. Changing signatures can trigger Keychain prompts. The project does not export signing keys, broaden Keychain ACLs or bypass Gatekeeper.

## QA tools

`--veil-qa` explicitly enables a local Chromium debug endpoint (default port 9223), diagnostic files and a build-specific synthetic profile. These interfaces can control pages and inspect their data. Use disposable profiles, no personal accounts and no secrets. Normal launches do not enable them. The fixture HTTP server binds to `127.0.0.1` only.

Treat QA logs, exports, screenshots, traces and profiles as private. They are excluded from publication, not automatically anonymized. The literal `user:secret@example.com` appears only as a deliberate synthetic credential-removal test fixture.

## Dependencies

DEPENDENCIES.json pins the official CEF archive by SHA-256. This verifies selected bytes, not ongoing upstream security support. Review Chromium/CEF security releases and update the pin deliberately; there is no automatic update service yet.

Python tool versions are pinned but wheel hashes are not locked. No dependency binaries, signing identity or browser profiles are committed.

## Publication guard

Run scripts/audit_public.py on the tree, staged bytes, history and exported archive, together with Gitleaks using redaction. The guard reports paths and categories, never matched secret values. These checks reduce accidental exposure; they do not prove absence of every secret or application vulnerability.
