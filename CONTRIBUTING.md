# Contributing

Keep code comments, issues and documentation in English. Build with scripts/bootstrap.py and scripts/build.sh, then run scripts/test.sh. Use synthetic data and an isolated profile for native QA.

Describe the user-visible change, validation and open limitations. Before committing, run scripts/audit_public.py with --tree, --staged and --history, plus Gitleaks with --redact.

Do not commit generated projects, dependencies, profiles, signing material, raw logs, personal screenshots or device/account identifiers. Ignored files can be force-added, so always audit staged bytes. See SECURITY.md for safe vulnerability reporting.

Preserve Chromium's sandbox, before-unload negotiation, private context isolation and conservative tab-sleep protection. Keep physical, model, native and energy evidence distinct.

The project-wide license has not been selected. Public visibility alone does not grant rights to redistribute or relicense original code.
