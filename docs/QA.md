# Verification

This is a development preview. Keep compilation, model/storage tests, observed native behavior, physical interaction and measured energy as separate evidence.

```sh
bash scripts/test.sh
python3 scripts/audit_public.py --tree
python3 scripts/audit_public.py --staged
python3 scripts/audit_public.py --history
gitleaks git . --pre-commit --staged --redact
gitleaks git . --redact
```

The Swift suite covers organization/import/recovery, window selection, favicon isolation, cache lifetime, no-op persistence, sleep protection, stable sidebar dwell and resource normalization. Native resource tests calibrate live/reaped child CPU against getrusage; Python checks the macOS timebase conversion. Output stays under ignored .work/.

The publication checkout passed 43 Swift model/storage/cache tests, 5 publication-guard tests, native resource calibration and Python CPU-counter calibration on 2026-11-06. Its arm64 Release build passed deep/strict ad-hoc signature verification. This does not establish the pending native interaction checks below.

## Native fixtures

```sh
python3 Tests/fixture_server.py
bash scripts/run.sh --qa --veil-url=http://127.0.0.1:8765/
```

Synthetic loopback fixtures exercise navigation, forms, media, downloads, horizontal scrolling and cookies. QA enables debugging/diagnostics: use disposable profiles and no personal logins. VEIL_APP selects a specific bundle. Read SECURITY.md.

Tests/benchmark.py and Tests/idle_sample.py measure process-family resources/action handling. Action timestamps exclude compositor presentation; AC idle samples do not establish battery life.

## Evidence limits

Earlier development observations exercised navigation, command routing, media, fixture downloads, Quick Look, private-context reset, renderer crash/retry, two-window close cancellation and page Undo/Redo. These are not a fresh full UI pass for this public snapshot.

Pending: the new Performance window's native controls/layout/lifecycle; physical trackpad/drag/hover; the full visual/accessibility/display-scale matrix; authenticated sites/OAuth/passkeys; launch/hitch traces, long soaks and battery-powered energy checks; every claimed supported OS/SDK combination.

Standard CEF packages do not establish Widevine/proprietary-codec/extension compatibility. Extensions are deferred. No complete Arc parity or production hardening is claimed. Private raw logs, profile paths, account references, screenshots and design-file links are intentionally excluded.
