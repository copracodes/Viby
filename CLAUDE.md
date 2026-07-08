# CLAUDE.md — Viby

Viby is a premium Android-first music player (local files + Subsonic
servers) built with Flutter, Material 3, Riverpod, and drift.

- **Dart package:** `viby`
- **Android applicationId / namespace:** `com.copra.viby`
- **iOS bundle id:** `com.copra.viby`

This file governs every session. Read it before writing code and keep it true.

---

## Architecture rules (non-negotiable)

1. **Playback goes through one facade.** UI and state code MUST NOT import
   `just_audio`, `audio_service`, or `audio_session` directly. All playback flows
   through `lib/audio/player_service.dart`. If you need a new playback capability,
   add a method to that facade — never reach around it.

2. **One `Track` model.** There is a single `Track` model in
   `lib/data/models/`. It carries a `source` enum with values `local` and
   `subsonic`. Do not create per-source track classes; branch on `source`.

3. **Library reads are streams.** All reads from the library come from drift
   `watch()` streams (reactive by default). Do not add one-shot `get()` reads for
   list/detail UI — the UI reacts to stream changes.

4. **State lives in `lib/state/`.** Application state is expressed as Riverpod
   **codegen** providers (`@riverpod`, generated with `riverpod_generator`).
   Widgets read providers; they never own long-lived business state.

5. **Data sources are isolated.** `lib/data/sources/local/` (on-device audio via
   `on_audio_query`) and `lib/data/sources/subsonic/` (remote API via `dio`) are
   the only places that talk to the outside world. They return domain models, not
   raw plugin/DTO types.

6. **Platform effects use the capability-flag pattern.** Platform-specific audio
   capabilities (the equalizer today; iOS/Darwin effects later) are gated behind
   a factory that returns a *capable* implementation on supported platforms and a
   **no-op** one elsewhere, both behind one interface — callers never branch on
   `Platform`. The template is `audio/eq_service.dart`: `EqEngine.build()`
   constructs the real just_audio effects + `AudioPipeline` only on Android
   (`capable == true`) and a null-pipeline engine everywhere else; `EqService`
   has `PlatformEqService` (real) and `NoopEqService` (`capable == false`, all
   methods no-op, `EqRuntimeState.unsupported()`). Effects that must attach at
   *player construction* (the pipeline) are built in `main()` before
   `AudioService.init` and injected via provider override, exactly like
   `PlayerService`. To add iOS EQ later: add a Darwin branch to `EqEngine.build`
   + a Darwin path in `PlatformEqService` — no UI/state changes.

### Layer sketch

```
ui/ (screens, widgets, theme)      ← Flutter widgets, no business logic
  │  reads Riverpod providers
state/                             ← @riverpod codegen providers
  │  calls facades / repositories
audio/player_service.dart          ← the ONLY entry point to just_audio/audio_service
data/
  db/                              ← drift database + DAOs (watch() streams)
  models/                          ← Track (+ future domain models)
  sources/local/                   ← on_audio_query
  sources/subsonic/                ← dio + Subsonic API
  cache/                           ← artwork / response caching
core/                              ← router, cross-cutting utilities
```

---

## Database (`lib/data/db/`)

Schema-first drift. Tables live in `tables.dart`, the `@DriftDatabase` in
`viby_database.dart`, and one DAO per concern under `daos/` (all reads are
reactive `watch()` streams; multi-row writes run in transactions/batches).

**ID strategy (deterministic string ids).** Track/album/artist primary keys are
deterministic strings, never autoincrement:

- local: `local:<mediaStoreId>`
- subsonic: `subsonic:<serverId>:<remoteId>`

A track carries its `albumId`/`artistId` as these same deterministic ids (plain
keys, not enforced FKs — the scanner may write a track before its album/artist
on a rescan; joins resolve by id). This makes rescans **idempotent upserts** (same
id → update in place, never duplicate) and removes any need for cross-source join
tables. Playlist ids are DAO-minted (`playlist:<micros>-<rand>`), not
source-derived. Server passwords are **never** in the DB — they live in
`flutter_secure_storage` keyed by the server row id.

Foreign keys are ON (`PRAGMA foreign_keys`). Cascades: deleting a playlist
removes its entries; deleting a track removes its history and cache entries.

**Schema-change policy: any schema edit = a new migration + a migration test.**
Bump `schemaVersion`, add an `if (from < N)` block in the `MigrationStrategy`
`onUpgrade`, and add a test — never mutate an existing version's shape in place.

---

## Commands

| Task | Command |
| --- | --- |
| Install deps | `flutter pub get` |
| Codegen (watch) | `dart run build_runner watch --delete-conflicting-outputs` |
| Codegen (once) | `dart run build_runner build --delete-conflicting-outputs` |
| Analyze | `flutter analyze --fatal-infos` |
| Test | `flutter test` |
| Run (Android) | `flutter run` |

`riverpod_lint` runs via `custom_lint` and is included in `flutter analyze`.

---

## Conventions

- **File naming:** `snake_case.dart`. One primary public class per file; the file
  name matches the class (`player_service.dart` → `PlayerService`).
- **No business logic in widgets.** Widgets render and dispatch. Logic lives in
  providers (`state/`), the player facade, or `data/` repositories.
- **Every feature lands with a test.** No feature PR without a matching test in
  `test/`. Prefer widget tests for UI and unit tests for providers/repositories.
- **Generated files are not committed.** `*.g.dart` (and friends) are
  git-ignored; CI regenerates them. Never hand-edit generated output.
- **Const by default.** `prefer_const_constructors` is enforced; declare return
  types explicitly; no `dynamic` calls (`avoid_dynamic_calls`).
- **Theme, don't hard-code.** Colours/typography come from `ui/theme/app_theme.dart`
  via `Theme.of(context)`.
- **Unknown metadata has one display rule.** MediaStore reports missing
  artist/album as the literal `<unknown>` (and null/empty happens too). Never
  format these inline — use the `DisplayNames` extension in
  `lib/core/display_names.dart` (`name.artistOrUnknown` / `name.albumOrUnknown`)
  everywhere a name is shown, so "Unknown artist" / "Unknown album" is defined
  in exactly one place.
- **Artwork renders through one widget.** All album art goes through
  `ui/widgets/album_art.dart` (`AlbumArt` / `AlbumArt.expand`), which resolves the
  on-disk file from `artworkKey` and falls back to a placeholder. Don't build
  `Image.file` paths in screens.

---

## Tooling notes

The installed toolchain is Flutter 3.29.3 / **Dart 3.7.2**. On this SDK the
newest `drift`/`riverpod` codegen releases (which require Dart ≥ 3.8) do not
resolve, so the stack is held at the latest compatible line: **Riverpod 2.6.x**
(codegen) and **drift 2.26.x**. Bump these together with a Flutter upgrade, not
in isolation. Exact versions are pinned in `pubspec.lock` (committed).

The on-device media-query package is **`on_audio_query_pluse`**, a maintained
fork of the discontinued `on_audio_query`. The original declares no Android
`namespace` and fails to build under AGP 8; the fork is API-compatible
(`OnAudioQuery()`) and AGP 8 clean. Keep using the fork.

**Its permission gate requires BOTH `READ_MEDIA_AUDIO` and `READ_MEDIA_IMAGES`
on Android 13+** (hardcoded pair), and its `querySongs` no-permission path is
buggy — it double-replies on the method channel and crashes the app *natively*
(`IllegalStateException: Reply already submitted`). So: declare + request both
permissions, and never call a query unless `permissionsStatus()` is true (the
scanner guards on exactly this). Revisit if the fork narrows the requirement to
audio-only.

`MainActivity` **must** extend `AudioServiceActivity` (not the stock
`FlutterActivity`) so the background audio handler and the UI share one cached
`FlutterEngine`. With plain `FlutterActivity`, `AudioService.init()` throws
"The Activity class declared in your AndroidManifest.xml is wrong…" at launch —
a native-integration failure invisible to `flutter analyze` and unit tests.

---

## Current phase

**Phase 1 — Library foundations.** Done: the walking-skeleton audio pipeline
(`audio_handler.dart` + `player_service.dart`, verified on-device); **Step 1.1
— the drift database** (`lib/data/db/`: schema, six reactive DAOs, in-memory
tests); **Step 1.2 — the local scanner** (`lib/data/sources/local/`:
permission flow via `permission_handler`, deterministic-id mapping + junk
filter, full/incremental scans with a cancelable `ScanProgress` stream, album
artwork extraction, and a throwaway `/debug-scan` screen); and **Step 1.3 — the
queue engine** — the `Track` domain model (`lib/data/models/track.dart`); a real
gapless playlist in the handler (in-place insert/remove/move via just_audio's
player-level playlist API — `ConcatenatingAudioSource` itself is deprecated in
the pinned 0.10.6); `QueueController` (`lib/state/queue_provider.dart`) owning
order/shuffle/repeat with pure, unit-tested index math (shuffle is engine-side —
just_audio's own shuffle stays OFF); debounced persistence + cold-start restore
(`queue_persistence.dart`, tolerant of deleted tracks); and a throwaway
`/debug-queue` screen. Restore is guarded so it can never block boot.

**Step 1.4 (Session A) — the UI shell + library browsing** is built: a
`StatefulShellRoute` bottom nav (Home / Library / Search / Settings) with a
persistent mini-player docked above it (`ui/shell/app_shell.dart`,
`ui/widgets/mini_player.dart`); Library tabs (Albums grid, Artists, Tracks,
Playlists-placeholder) with album/artist detail and tap-to-play wiring; Home
(recently played/added + scan CTA); debounced Search; Settings (rescan, theme
stub, Developer section housing the `/debug-*` tools, About). A `HistoryRecorder`
logs plays so "recently played" fills. The Impeller opt-out from Phase 1.3 pairs
with `splashFactory: InkRipple` in the theme (InkSparkle needs a shader that
fails on this device / in tests). Analyze clean; 72 tests green (widget tests for
the album grid, album-detail play wiring, mini-player, and the unknown-name
rule).

**Step 1.4 (Session B) — the basic Now Playing screen** is built
(`ui/screens/now_playing_screen.dart`): a full-screen modal route
(`fullscreenDialog`, opened by the mini-player tap) with large flexible artwork,
title/artist, an `audio_video_progress_bar` scrubber wired to
position/buffered/duration (a `bufferedPosition` stream was added to the facade),
a transport row (shuffle / prev / play-pause / next / repeat) with active-state
colours driving `QueueController`, a queue button opening a bottom sheet that
reuses the shared `QueueListView` (`ui/widgets/queue_list.dart`, also used by
`/debug-queue`), and simple swipe-down-to-dismiss. Intentionally plain — Phase 2
adds the gesture/animation treatment. A later pass added **transport
affordances**: `QueueState.hasNext`/`hasPrevious` (repeat-aware) dim Next at the
end of the queue and Previous when there's no prior track *and* position < 3s (in
both Now Playing and the mini-player, which gained a Next button), plus a
"N of M" queue-position indicator.

**Step 1.5 — playlists, play tracking, search recents** completes Phase 1's
functional feature set:
- **Playlists.** `PlaylistDao` gained `watchPlaylistSummaries` (grid cards:
  count + 2×2 collage via the pure `pickCollageKeys` = first 4 distinct arts),
  `watchPlaylistWithMeta` (detail), `watchPlaylistIdsContaining` +
  `toggleTrack` (add-to-playlist checkmarks). UI: Library › Playlists tab
  (grid + New-playlist dialog), `playlist_detail_screen.dart` (collage header,
  play/shuffle, reorder, swipe-remove, rename/delete-with-confirm), the enabled
  "Add to playlist" track sheet (`ui/widgets/add_to_playlist.dart`), and an
  album-detail overflow "Add album to playlist". Route `/library/playlist/:id`.
- **Play tracking.** `HistoryRecorder` was rewritten to record **once per
  index-session** at ≥80% position OR completion, driven by the
  position/index/duration/processingState streams (not UI events) — seek-back
  never double-counts, a track skipped before 80% is never logged.
- **Search recents.** New `Searches` table (**schema v2**: bumped
  `schemaVersion`, `onUpgrade` `createTable`, migration test) + `SearchDao`
  (record-on-result-tap, newest-10, clear-all; drift stores `DateTime` at
  1-second resolution, so `recordSearch` takes a test-only `at`). Search screen
  shows recent-term chips when the field is empty.

93 tests green (added: v1→v2 migration, SearchDao prune/order/clear, playlist
collage + toggle + containment, the 80% play-tracking rule).

**Step 1.6 — hardening (closes Phase 1).** Resilience + correctness at scale,
no new features:
- **Legacy tag encoding (mojibake repair).** `core/tag_encoding.dart` is a pure
  module: an embedded Windows-1256 (CP1256) table, `decodeCp1256`, a
  `looksSuspicious` pre-filter, and `bestDecoding` — a scoring heuristic that
  reinterprets a Latin-1-decoded string as CP1256 and keeps it only when it
  surfaces Arabic without adding garbage (clean ASCII/UTF-8 passes through
  untouched). `sources/local/id3_reader.dart` is a dependency-free ID3v1/v2.2/
  v2.3/v2.4 reader that returns Latin-1 frames byte-for-byte (so the CP1256
  bytes survive for re-decode) — chosen over the `audiotags` plugin for build
  robustness on this device + full unit-testability. `sources/local/
  tag_repair_service.dart` sweeps the DB: string re-decode first (fixes the
  common MediaStore-decoded-as-Latin1 case with no I/O), then a file re-read via
  a `RawTagReader` for lossy `?`/U+FFFD titles. Runs as a post-scan `ScanPhase.
  repair` (so **Settings › Rescan** repairs; progress reported). Files on disk
  are never modified; only DB rows change.
- **Scale (10k).** A debug `LibrarySeeder` (Settings › Developer: "Seed 10k" /
  "Clear synthetic") inserts 10k tracks / 800 albums / 400 artists straight into
  drift under the `local:synthetic:` id marker (clear removes exactly those).
  Scroll: fixed `itemExtent` on the Tracks/Artists lists, `cacheWidth`
  downsampling in the single `AlbumArt` widget, and a bumped image-cache budget
  at boot. Measured (in-memory, dev hardware): seed 10k ≈ 1.1s, **search 42ms**
  (< 100ms), **diff 26ms** (< 2s), **restore 500 ids 52ms** (< 500ms) — asserted
  in `test/perf/scale_perf_test.dart`, which prints the numbers.
- **Corrupt/missing files.** A new `playable` column (**schema v3**: `addColumn`
  migration + test). The audio handler catches `playbackEventStream` errors and
  routes around the bad track via the pure `decidePlaybackFault` (skip / wrap
  under repeat-all / stop-all-failed / stop-at-end), emitting a domain
  `PlaybackFault`. `FaultReporter` (read at app start) marks the track
  `playable = false` and shows a "Couldn't play X — skipped" SnackBar via a
  root messenger key; a rescan upserts `playable` back to true.
- **Lifecycle.** `LibraryScan` is keepAlive so an in-flight scan's progress
  survives a Settings rebuild/rotation (the scan itself lives in the keepAlive
  `LocalScanner`, whose `_scanning` guard makes a duplicate impossible). Queue
  restore stays unawaited + guarded, so even a large restore never blocks boot.

120 tests green (added: tag encoding + heuristic, ID3 fixture parsing, tag
repair round-trip, v2→v3 migration, fault decision + reporter, seeder + clear,
10k scale budgets). See `DEVICE_CHECKLIST.md` for the on-device verification
pass. **Phase 1 is complete and committed.**

## Phase 2 — beauty pass

**Step 2.1 — design system + album-art dynamic theming.**
- **Design tokens** (`ui/theme/tokens.dart`): the single source of truth for
  `Spacing` (4pt grid), `Radii` (sm/md/lg/full), `Motion` (durations
  fast/base/emphasized + the 350ms `themeMorph`; M3 curves standard /
  emphasizedDecelerate / emphasizedAccelerate), `Elevations` (dark-first —
  prefer M3 surface *tint* over shadows), and the `VibyType` type scale.
  `AppTheme.fromScheme` is the one place `ThemeData` is assembled, so the brand
  theme and the dynamic theme are structurally identical (only colours differ).
  Screens compose from tokens instead of magic numbers (hero surfaces swept;
  new UI must follow).
- **Dynamic theming** (`ui/theme/dynamic_theme.dart`): `palette_generator`
  extracts the dominant *vibrant* colour from the artwork file →
  `ColorScheme.fromSeed`. Variants: light / dark / **amoledBlack** (pure #000
  surfaces). Guards: `ensureContrast` holds primary-on-surface ≥ 4.5:1;
  near-monochrome art (`isNearMonochrome`) falls back to the brand purple seed.
  Cache: an in-memory `LruCache` (~50) over a drift `ArtworkPalettes` seed cache
  (**schema v4**, with a generic `Preferences` KV table; migration + test), so
  cold start themes instantly.
- **Scoping decision (documented per spec):** dynamic colour is a
  **now-playing-context** thing, **not** a whole-app strobe. Only the
  **mini-player** and **Now Playing** opt in (each wrapped in
  `DynamicThemeScope`, which lerps the `ColorScheme` over 350ms via
  `AnimatedTheme` → `ThemeData.lerp`). **Library / Home / Search / Settings stay
  on the calm base theme** so browsing doesn't flash a new colour with every
  track change.
- **Settings** now has a real theme-mode selector (System / Light / Dark /
  AMOLED) + a "Dynamic color from artwork" toggle, persisted via the
  `PreferencesDao` (`state/theme_providers.dart`; defaults applied synchronously
  so the first frame themes correctly, then hydrated from drift).

135 tests green (added: contrast guard, monochrome fallback, LRU eviction,
amoled surfaces, v3→v4 migration + palette/preferences DAO round-trips).

**Step 2.2 (session 1 of 2+) — the Now Playing flagship.** Structure,
transitions, and core gestures (micro-polish iterates on device feel):
- **One continuous surface.** The old `/now-playing` modal route,
  `NowPlayingScreen` and `MiniPlayer` are **gone**. In their place, a single
  `PlayerOverlay` (`ui/player/`) is *both* the docked mini-player (expansion 0)
  and full-screen Now Playing (expansion 1), driven by one `AnimationController`.
  It's a `Positioned.fill` sibling above the nav shell (`AppShell` restructured
  to a Stack); while collapsed it only occupies the mini-bar strip, so the shell
  stays interactive, and the column reserves that strip's height. Drag up / down
  and tap all drive the same controller; release settles by the pure
  `settleTarget` (fling completes, < 40% travel springs back). The artwork is a
  shared element whose rect lerps between the mini thumb and the full card.
- **Layout on the dynamic scheme.** Blurred artwork backdrop
  (`NowPlayingBackdrop`, `RepaintBoundary`-isolated + never watching position),
  scrim at 70% surface; artwork card scales 1.0↔0.94 on play/pause; themed
  scrubber with a scrub-time bubble (`PlayerProgress`); transport with springy
  press (`PressableScale`) + an `AnimatedIcon` play↔pause morph
  (`PlayerTransport`), disabled states per the 1.4 rules.
- **Artwork swipe-to-skip** (`ArtworkStage`): follows the finger with neighbour
  peek, commits at 35% or a fling, rubber-bands at the ends, and touches the
  queue **only on commit** (never mid-drag). Vertical (expand/collapse) vs
  horizontal (skip) disambiguate via the gesture arena.
- **Queue sheet**: "Up next" + the shared reorder/remove list + clear-with-confirm.
- Pure decision logic (`ui/player/player_transition.dart`) is fully unit-tested
  (settle state machine, swipe-commit threshold, previous-gating).

147 tests green. Session 2 is the micro-polish / feel pass (parallax tuning,
marquee, artist tap, interruption niceties) after on-device testing.

**Step 2.3 — Library & Home beauty pass.** The Now Playing design language now
runs across the whole app (same `tokens.dart`, same motion):
- **Reusable pieces.** `Shimmer` (skeleton, replaces load spinners), `AlbumArt`
  upgraded (shimmer-while-resolving + 200ms crossfade-in + optional 1px scheme
  `outline`), `EqualizerBars` (3-bar current-track indicator, freezes when
  paused), `StaggerScope`/`StaggeredEntrance` (one shared controller → entrance
  runs once on first build, not on scroll/rebuild), `ArtistAvatar` (initials on
  primary container), and a central `HapticsService` (`core/haptics.dart` +
  `state/haptics_providers.dart`, persisted enable flag).
- **Library.** Albums grid: staggered fade+rise entrance, outlined rounded-md
  art. Album & Artist detail: collapsing `SliverAppBar` headers (large art /
  avatar folding into a compact bar whose title fades in), Play + **tonal**
  Shuffle pair. `TrackTile` shows the equalizer on the current row (each visible
  row cheaply watches `currentTrack?.id == id`). Tracks tab: alphabet
  `FastScrollbar` (draggable thumb + letter bubble) for the 10k case.
- **Home.** Time-of-day greeting (`greetingForHour`), horizontal strips with
  press-scale cards (0.97) + "See all", a **"Your top tracks"** section gated by
  `shouldShowTopTracks` (≥5 distinct plays, `topTracksProvider` →
  `watchMostPlayed`), and a welcoming empty state. Home lost its AppBar (the
  greeting is the header).
- **Haptics.** Light impact on play/pause, skip commit, reorder drop, playlist
  add; selection tick on shuffle/repeat; nothing on scroll/drag. Settings ›
  Feedback toggle.

Pure logic (`ui/library/fast_scroll.dart`, `ui/home/home_logic.dart`) is
unit-tested; a widget test pins the stagger's run-once behaviour. 158 tests
green. Subsonic remains Phase 3.

## Phase 3 — Pro audio

**Step 3.1 — Equalizer.** A flagship Pro feature built on Android's platform
`AudioEffect`s (capability-flag pattern, rule 6 above), so iOS/desktop degrade
cleanly to a no-op behind one interface.
- **Pipeline.** `audio/eq_service.dart`: `EqEngine.build()` constructs an
  `AndroidEqualizer` + `AndroidLoudnessEnhancer` in an `AudioPipeline`
  (Android only) — built in `main()` *before* the player (a pipeline must attach
  at player construction) and handed to `VibyAudioHandler(eqEngine:)`; the same
  effect instances are driven by `PlatformEqService`. The service exposes a
  reactive `EqRuntimeState` (enabled, per-band freq+gain, min/max dB, loudness,
  active preset, `modified`). just_audio only reports its real band layout after
  the player first connects, so the UI shows the saved/fallback bands
  immediately and the platform gains reconcile on first playback (no audible
  pop); enable + loudness arm pre-playback.
- **Persistence (schema v5).** `eq_settings` (single row) + `eq_presets` (user
  presets), `EqDao`, migration + test. Band gains are stored as a JSON map keyed
  by **center frequency** (not band index), so a curve saved on a 5-band device
  restores correctly on a 3-/10-band one — the service re-normalizes onto
  whatever bands the platform reports. Restored on launch before first playback.
- **Presets.** Seven built-ins (Flat, Bass boost, Vocal, Rock, Jazz, Electronic,
  Podcast) authored as frequency-response *curves* and `normalizeCurveToBands`'d
  (log-frequency interpolation) onto the device's actual bands — never assumes a
  band count. User custom presets: save current sliders under a name, rename,
  delete (`audio/eq_preset.dart`, all pure + unit-tested).
- **UI** (`ui/screens/eq_screen.dart`, entry from Now Playing overflow +
  Settings › Audio): large master switch, preset chips (filled = active),
  vertical per-band sliders with dB labels + a 0 dB center detent (snap within
  ±0.5 dB), real-time. A `CustomPainter` frequency-response curve
  (`ui/eq/eq_curve_painter.dart`, smooth Catmull-Rom spline, primary-tinted
  fill) animates as sliders move. Loudness enhancer is a separated horizontal
  slider with a caption. Editing an active preset shows "Custom (based on Rock)"
  + a Save affordance (`eqStatusLabel`).

184 tests green (added: preset normalization on 3/5/10-band layouts,
frequency-keyed restore across layouts, detent snap, modified-state + status
label, gain-map JSON round-trip, v4→v5 migration + EqDao round-trip, EQ screen
widget test). **Device pass complete** (S22, Android 16): real-time band drags
audible with no glitches/dropouts, curve animates smoothly, 0 dB detent, presets
apply/animate, modified-preset state, loudness enhancer, EQ persists across app
restart, and it affects both Bluetooth and speaker output. Subsonic remains
Phase 3.

**Step 3.2 — the theme collection.** Named, hand-crafted visual themes (aurora
gradients, glass, soft depth) that *extend* the 2.1 token + dynamic-colour
system — the token scale, motion and the contrast guard all still apply.
- **Model** (`ui/theme/viby_theme.dart`): `VibyTheme` = `ColorScheme` +
  `BackgroundSpec` (sealed: solid | linearGradient | aurora `GlowBlob`s) +
  `SurfaceSpec` (sealed: opaque | tinted | glass). Specs JSON-serialize
  (round-trip tested). `acceptsDynamicSeed` gates whether album-art colour may
  swap a theme's primary.
- **The six** (`ui/theme/theme_collection.dart`, one file to tune by eye):
  Classic Light/Dark (unchanged ids, accept dynamic seed), Midnight Aurora
  (near-black + violet/blue/magenta glow, glass nav), Nebula (purple→plum wash,
  pink accent, tinted), Frost (light, green-tinted glass), Onyx (charcoal, green
  accent, NO blur — the perf-safe dark option, accepts dynamic seed). Aurora and
  gradient themes lock their identity (no dynamic seed) so colour doesn't fight
  the art direction; Now Playing's palette-tinted backdrop still applies
  everywhere (contextual, per the 2.1 decision).
- **Plumbing** (invasive, its own commit): every scaffold/app-bar/canvas is
  transparent (theme-level, so no per-screen edits) over one `AppBackground`
  mounted in `MaterialApp.builder`. **Aurora is a STATIC layer** — blobs
  composed into a cached `ui.Image` once per theme+size (`toImageSync`), redrawn
  only on theme/size change, in a `RepaintBoundary` (zero background repaints on
  scroll). Never a live `BackdropFilter` for backgrounds.
- **Glass budget:** the ONLY live `BackdropFilter` for chrome is the nav bar
  (`GlassPanel`) on glass themes; cards/sheets *fake* glass with a translucent
  tint + hairline border and let the background show through (the perf budget
  caps live blurs at ~2: nav + an active sheet). Contrast guard runs over the
  brightest aurora blob region and auto-darkens blob opacity if body text would
  fail 4.5:1.
- **Picker** (Settings › Appearance): a horizontal gallery of live preview cards
  (real background + faux mini-player, ringed selection, Pro badge on 3-6),
  plus system-follow, AMOLED override (forces pure-black base on dark themes;
  aurora blobs survive on black), and the dynamic-colour toggle (disabled with
  an explanation on non-accepting themes). Switching animates the app scheme
  (`themeAnimationDuration = 350ms`) and cross-fades the background.
- **Persistence:** theme selection lives in the **existing v4 Preferences KV
  store** (`theme_id` / `theme_system_follow` / `theme_amoled` / `dynamic_color`)
  — theme choice is a preference, not a schema change, so *no drift migration is
  needed* (a no-op schema bump would violate the schema policy). The provider
  hydrates and migrates the legacy `theme_mode` value once.

**Pro badge pattern (established here for later gating).** Pro-marked features
carry `ProBadge` (`ui/widgets/pro_badge.dart`) but gating is one const:
`kProThemesUnlocked` in `core/pro.dart` (currently `true`, `TODO(3.4)`). Flip it
to `ref.watch(proProvider)` when billing lands and gate the action (show a
paywall) — a one-line change; the badge already renders.

Analyze clean; 209 tests green (BackgroundSpec serialization, blob contrast
guard + auto-darken, per-theme coherence, resolveActiveTheme, dynamic-seed
gating, theme-settings persistence + legacy migration, preview-card widget
test). **Device pass pending** (per spec): live with each theme; expect a
tuning iteration on blob positions/opacities + glass tint values (isolated in
`theme_collection.dart`). Verify the perf budget on S22 (fling Library in
Midnight Aurora + Frost = zero jank; repaint-rainbow shows no aurora repaints
on scroll; Now Playing drag 60fps on every theme). Subsonic remains Phase 3.
