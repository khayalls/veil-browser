# VEIL

A Chromium-powered macOS browser inspired by Arc, with Spaces, fluid gestures, customizable glass UI, and a keyboard-first workflow.

VEIL uses AppKit and Swift around Chromium Embedded Framework (CEF), connected through Objective-C++. This is an Apple Silicon development preview. Physical gesture quality, accessibility coverage, authenticated-site compatibility and battery performance remain works in progress. Chrome extensions are deferred.

## Features

- Sidebar with Favorites, Space-specific pins, two-level folders, drag and drop, and temporary tabs.
- Spaces with persistent organization, independent window selection and configurable colors/backgrounds.
- Centered Command-T search for addresses, local tabs, history, Spaces and commands.
- Native glass, hidden-sidebar edge reveal, reduced-motion and reduced-transparency support.
- Two-finger history navigation that yields to editors, canvases and horizontal scrollers.
- Lower-right media controls, downloads, history, archive and Quick Look.
- Lazy session restore, guarded tab sleeping, Keep Awake and an on-demand Performance window.
- Private windows with memory-only workspace metadata and an ephemeral CEF request context.

The Performance window is newly implemented and still needs native interaction validation. Website content runs in Chromium; the browser interface is native macOS.

## Requirements and build

Apple Silicon, macOS 14 or later, full Xcode with a macOS SDK, and Python 3 with `venv`. Native Liquid Glass is used on macOS 26 or later; earlier systems use material fallbacks. Development used Xcode 27.1; other supported OS/SDK combinations have not all been tested.

```sh
git clone https://github.com/khayalls/veil-browser.git
cd veil-browser
python3 scripts/bootstrap.py
bash scripts/build.sh --deliver
bash scripts/test.sh
open dist/VEIL.app
```

Bootstrap downloads the official CEF archive pinned by SHA-256 in DEPENDENCIES.json and installs pinned CMake/Ninja/Python tooling into `.work/`. Dependencies, build products and test output are ignored by Git. No API keys or developer account are required for a local ad-hoc build.

Open `Open in Xcode.command` to generate the Xcode project, or run:

```sh
VEIL_GENERATOR=Xcode bash scripts/build.sh --deliver
```

Select the VEIL scheme and My Mac. If an unsigned CMake invocation stalls under Documents, `bash scripts/build-scratch.sh --deliver` builds in a disposable temporary directory. `VEIL_WORK` selects an absolute dependency/build cache, `VEIL_JOBS` controls compilation parallelism, and `VEIL_SIGN_IDENTITY` optionally selects an existing signing identity. Never commit signing material.

## Everyday controls

| Shortcut | Action |
| --- | --- |
| ⌘T / ⌘L | Floating search / edit current address |
| ⌘↵ in command bar | Open in a new tab |
| ⌘W / ⇧⌘W | Close tab / window |
| ⇧⌘T | Reopen closed tab |
| ⌘D / ⌘S | Pin or unpin / toggle sidebar |
| ⌘[ / ⌘] | Back / forward |
| ⌘R / ⇧⌘R | Reload / reload without cache |
| ⌃Tab | Recent tabs |
| ⌘1…9 | Select visible tab |
| ⌃⌥1…9 | Select Space; may conflict with VoiceOver |
| ⌘⌥← / → | Previous / next Space |
| ⌘Y / ⇧⌘J | Library / Downloads |
| ⇧⌘K | Archive ordinary tabs in the Space |
| ⌘, | Settings and shortcut remapping |

Settings → Colors & Background previews and applies per-Space themes. Escape or an outside click closes the command bar. Closing a pin parks its page; Remove Pin and Close removes the pin.

## Data and security

Normal browser data lives in `~/Library/Application Support/VEIL`. SQLite workspace metadata contains URLs, history, titles and download paths; it is not an encrypted vault. CEF manages website data in Engine and uses a VEIL-specific Keychain item for cookie encryption. Spaces share website logins. Explicitly saved private-window downloads remain on disk.

Normal launches do not enable VEIL's QA debug endpoint. The Chromium sandbox remains enabled and website permissions require prompts. See [SECURITY.md](SECURITY.md). Do not upload profiles, workspace exports, personal screenshots or raw QA logs.

## Verification and contribution

See [docs/QA.md](docs/QA.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/ROADMAP.md](docs/ROADMAP.md) and [CONTRIBUTING.md](CONTRIBUTING.md). Passing tests/builds do not establish daily-use readiness or complete Arc parity. Standard CEF packages do not establish Widevine, proprietary codec or Chrome extension compatibility.

```sh
python3 scripts/audit_public.py --tree
python3 scripts/audit_public.py --staged
python3 scripts/audit_public.py --history
gitleaks git . --pre-commit --staged --redact
gitleaks git . --redact
```

A ready-to-enable CI workflow is provided at [docs/public-source-workflow.yml](docs/public-source-workflow.yml). It is a template, not an active GitHub Actions workflow; enabling it requires GitHub credentials with workflow permission.

## Notices

Phosphor SVGs are MIT-licensed; their full notice is in Resources/Phosphor-LICENSE.txt. CEF/Chromium license and credits are copied from the pinned dependency into built apps. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). VEIL is independent and is not affiliated with Arc, The Browser Company, Apple or Google.

No project-wide license has been selected for VEIL's original code. Public visibility alone does not grant reuse rights; third-party material retains its respective license.
