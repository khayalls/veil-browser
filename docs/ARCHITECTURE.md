# Architecture

VEIL combines an AppKit/Swift shell with CEF page rendering through Objective-C++.

| Area | Files under Sources/ |
| --- | --- |
| Lifecycle and menu routing | Application.swift, Bootstrap.swift, main.mm |
| Browser window and page engines | BrowserWindow.swift, VEEngine.mm, VEEngine.h |
| Sidebar and search | Sidebar.swift, CommandPanel.swift, Components.swift |
| Glass and appearance | GlassSurface.swift, SpaceAppearanceWindow.swift, SettingsWindow.swift |
| SQLite organization and recovery | Workspace.swift, WorkspaceImport.swift, WorkspaceRecovery.swift |
| Library and media | LibraryWindow.swift, MediaCard.swift |
| Resource and sleep policies | PerformanceWindow.swift, ProcessResources.mm, ProcessResourceReading.swift, TabSleepProtection.swift |
| Bounded renderer hints | Renderer.cc |
| QA-only scenarios | QABenchmark.swift, QAPerformanceScenario.swift |

## Rendering and organization

The CEF host is a non-layer-backed native view. Glass chrome/corner masking use sibling surfaces; moving CEF under a layer-backed glass ancestor can break presentation.

Favorites span Spaces in one profile. Pins and two-level folders belong to Spaces. Window selection is independent; organization is shared. Closing a pin parks its page rather than deleting the pin.

SQLite/WAL stores validated transactional organization with atomic recovery snapshots. Exports omit history/downloads/archive but still contain user URLs. Private workspace metadata and private favicon caching stay in memory. CEF owns website storage separately.

## Interaction

Command-T opens a centered overlay without creating an empty tab; Command-L edits the current address. Sidebar edge reveal uses dwell/cancellation rather than resetting on every pointer movement. AppKit history swipe tracking supports cancellation and history bounds while yielding to page editors, canvases and horizontal scrollers. Reduce Motion and Reduce Transparency are respected.

Static designs and model tests do not validate physical gesture or animation quality.

## Resources

Restored tabs load lazily. Selected pages, media/capture/WebRTC, observed uploads/downloads, dirty inputs, loading, unknown state and Keep Awake protect against sleeping. Pressure/Low Power Mode shorten eligibility. Unloading cannot reconstruct arbitrary JavaScript or unsaved form state.

Performance samples only the browser process family while visible and stops when closed, hidden, minimized or occluded. CPU uses one-logical-core normalization. Memory is an approximate aggregate physical footprint; shared allocations can be counted in multiple processes. No per-tab memory attribution is claimed.

Renderer hints are bounded UI data, not a privileged native command interface. See SECURITY.md.
