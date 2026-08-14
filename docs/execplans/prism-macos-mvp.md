# Prism macOS MVP — Feature ExecPlan

This is a living implementation plan. Keep `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` current while work proceeds.

## Purpose

Build Prism, a quiet native macOS 14+ menu-bar utility that answers where the Mac currently exits to the internet. A user can read the localized country directly from the menu bar, open a compact popover for IP and network details, open a full dashboard and local history, and configure refresh, appearance, notifications, and launch-at-login behavior.

## Progress

- [x] 2026-08-14: Read the reference repository, README, source, resources, screenshot, and releases.
- [x] 2026-08-14: Lock product name, dashboard scope, sandbox target, provider strategy, and MVP exclusions.
- [x] 2026-08-14: Create this persistent ExecPlan before implementation.
- [x] 2026-08-14: Write reference analysis and product specification.
- [x] 2026-08-14: Create the Swift 6/macOS 14 Xcode project, app target, unit tests, UI tests, resources, and entitlements.
- [x] 2026-08-14: Implement models, providers, refresh pipeline, caching, history, settings, notifications, and launch-at-login.
- [x] 2026-08-14: Implement status item, popover, dashboard, history, settings, localization, and accessibility.
- [x] 2026-08-14: Generate and package an original Prism icon with all ten macOS icon slots.
- [x] 2026-08-14: Build, test, launch, visually inspect, and correct the app; verify the supplied no-signing commands.
- [x] 2026-08-14: Complete outcomes and retrospective.

## Surprises & Discoveries

- The workspace was empty and was not a Git repository at task start.
- No project-local `.agent/PLANS.md` or global `~/.codex/PLANS.md` template exists, so this self-contained feature format is used.
- Here's current source is ahead of its latest public GitHub release: inspected main commit `47da020` identifies v0.34.0 work while the public release page lists v0.33.0.
- ipwho.is free responses provide location/network data but not reliable security flags; anonymous ipapi.is provides a minimal privacy classification with a 100-request/client-IP/day quota. Prism therefore classifies only on new IPs and caches the result.
- A fresh Xcode installation required `xcodebuild -runFirstLaunch` before the macOS SDK and test services were usable.
- The macOS 14 deployment target does not support the newer rotate symbol effect, so the refresh indicator uses a reduce-motion-aware SwiftUI rotation instead.
- `UserDefaults.integer(forKey:)` returns zero for an absent key, which collided with the valid “network changes only” raw value. Initialization now distinguishes absence with `object(forKey:)` and defaults to one minute.
- A view-level dynamic `preferredColorScheme(nil)` did not reliably clear a previously selected dark scheme. Appearance is now applied once at the AppKit application boundary so SwiftUI content and native toolbars remain synchronized.
- Xcode 26's macOS UI test runner remains waiting for the system automation handshake in this host, both unsigned and ad-hoc signed. The UI test target compiles; Dashboard, History, all Settings tabs, copy semantics, localization, toolbar navigation, and light/dark behavior were exercised through the local Computer Use accessibility bridge instead.

## Decision Log

- 2026-08-14: Use `NSStatusItem` and `NSPopover`, not `MenuBarExtra`, because right-click behavior and dynamic label control are product requirements.
- 2026-08-14: Use SwiftUI for content and AppKit only for status item, popover/window lifecycle, and reliable Settings bridging.
- 2026-08-14: Use ipify for independent IPv4/IPv6 discovery; ipwho.is with ip.guide fallback for geolocation; ipapi.is for best-effort privacy classification.
- 2026-08-14: Query geolocation and privacy only when the address set changes; periodic refresh only checks public addresses.
- 2026-08-14: Prefer IPv4 for the primary location lookup and use IPv6 when IPv4 is unavailable.
- 2026-08-14: Enable App Sandbox with outbound network and user-selected launch-at-login APIs; exclude self-update functionality.
- 2026-08-14: Persist only local JSON in Application Support and preferences in UserDefaults; no telemetry or accounts.
- 2026-08-14: Use emoji flags generated from ISO codes so no reference flag assets are copied.
- 2026-08-14: Select the third generated icon direction: a bold blue sphere with negative-space bands and one outbound arrow; archive its prompt and source under `docs/design`.
- 2026-08-14: Apply the chosen appearance through `NSApp.appearance` and observe the setting from `AppEnvironment`; a single AppKit boundary avoids mixed SwiftUI/AppKit window chrome.
- 2026-08-14: Import AppIntents in build modules to satisfy Xcode 26 metadata extraction and keep the clean application build warning-free; Prism does not publish an App Intent in this MVP.
- 2026-08-14: Keep the no-signing `Prism` scheme deterministic by running its unit suite only. The compiled UI suite has a separate shared `PrismUITests` scheme because macOS UI automation requires a signed runner and host authorization.

## Context and Implementation Plan

Create a conventional Xcode app with synchronized source groups. `AppEnvironment` is the composition root. Actor-backed services own shared mutable network and persistence state. `NetworkStatusViewModel` is `@MainActor @Observable` and exposes a single `NetworkStatus` to SwiftUI and the status controller. `RefreshCoordinator` reacts to timers, `NWPathMonitor`, system sleep/wake, and manual refresh while coalescing work in `NetworkLookupService`.

The status item renders localized text from `MenuBarLabelRenderer`. Left click toggles an application-defined popover; right click presents Refresh, Open Details, Settings, and Quit. The dashboard is an AppKit-owned resizable `NSWindow` hosting SwiftUI. Settings remains a native SwiftUI `Settings` scene; a small SwiftUI bridge captures `OpenSettingsAction` for AppKit callers.

`NetworkInfoCache` preserves the last successful result. `NetworkHistoryStore` adds a baseline and only records when IPv4, IPv6, country, or ASN differs, retaining 100 entries. Notification permission is requested only when the setting is enabled and no notification is sent for the initial baseline.

All UI strings live in `Localizable.xcstrings` with English and Simplified Chinese values. Views use semantic colors, the restrained blue accent, monospaced IP text, icon accessibility labels, keyboard shortcuts, and short non-spring transitions.

## Concrete Steps

1. Write `REFERENCE_ANALYSIS.md` and `PRODUCT_SPEC.md` before code.
2. Create `Prism.xcodeproj`, application/test targets, Info.plist, sandbox entitlements, asset catalog, and localization catalog.
3. Implement models and pure formatting/persistence types with tests.
4. Implement injected URLSession providers, sequential fallback, partial dual-stack behavior, timeouts, cancellation, and lookup coalescing with fixture tests.
5. Implement state observation, scheduling, network and sleep/wake triggers, cache/history, notifications, and settings.
6. Implement status item, popover, dashboard/history, settings, commands, previews, and accessibility.
7. Generate an original icon with the built-in image generation path, select the best small-size result, and create all required app-icon renditions.
8. Run `xcodebuild` build/test under no-signing, then launch an ad-hoc signed Debug build for runtime and visual QA.
9. Exercise direct/VPN/offline, light/dark, English/Chinese, IPv4/IPv6, settings, history, and keyboard flows; correct defects and update this plan.

## Validation and Acceptance

Run:

    xcodebuild -project Prism.xcodeproj -scheme Prism -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO clean build
    xcodebuild -project Prism.xcodeproj -scheme Prism -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test

The build must complete without warnings. Provider, fallback, cache, history, settings, and renderer tests must pass. At runtime the app must show a meaningful cold-start state, preserve cached data without presenting it as fresh, react to path changes after roughly 1.5 seconds, keep the popover anchored during refresh, and expose all required actions in both languages and dark mode.

## Idempotence and Recovery

All file writes are atomic. Corrupt cache/history files decode as empty and are replaced on the next successful write. Re-running project creation should not be necessary; subsequent changes are made with patches. Failed network requests do not clear the last successful cache and do not append history. The app never retries inside a single refresh; the scheduler is the retry layer.

## Outcomes & Retrospective

Prism now builds as a native sandboxed macOS 14 accessory app with a dynamic status item, stable popover anchor, dashboard, local history, five-tab settings window, dual-stack address discovery, provider fallback, cached metadata/privacy results, cache-safe failure states, network/sleep scheduling, local notifications, launch-at-login, full English/Simplified Chinese localization, accessibility labels, keyboard shortcuts, and an original multi-resolution icon.

The exact warning-free no-signing clean build completed successfully. The default no-signing test scheme executed 16 tests with zero failures, covering both address families and partial success, both GeoIP wire formats and fallback, privacy classification, coalesced refresh, metadata reuse, hard timeout, cancellation, cache staleness, history corruption/deduplication/capping, settings defaults/transitions, and menu-label formatting. JSON catalogs validate, all `String(localized:)` keys exist, and every catalog entry has a Simplified Chinese value.

Runtime QA used a locally signed sandbox build and live network providers. The Dashboard returned IPv4/IPv6, localized country, city, ISP, organization, ASN, timezone, and provider data; Overview/History navigation, Settings tabs, copy-to-checkmark feedback, command shortcuts, and complete light/dark/system appearance switching were observed through the accessibility tree and screenshots. The 16/32/128 pt icon renditions were inspected directly.

The host's Xcode 26 UI automation runner waits for an OS automation handshake before the UI test method begins. The UI target compiles and remains available through the dedicated `PrismUITests` scheme, while equivalent read-only UI flows were completed through the already-authorized Computer Use bridge. Physical VPN/Wi-Fi/hotspot, IPv4-only, IPv6-only, login-item relaunch, and notification permission matrices still require running the signed app on the intended Mac because those checks depend on external network and OS state.
