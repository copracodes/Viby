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
artwork extraction, and a `/debug-scan` screen); and **Step 1.3 — the
queue engine** — the `Track` domain model (`lib/data/models/track.dart`); a real
gapless playlist in the handler (in-place insert/remove/move via just_audio's
player-level playlist API — `ConcatenatingAudioSource` itself is deprecated in
the pinned 0.10.6); `QueueController` (`lib/state/queue_provider.dart`) owning
order/shuffle/repeat with pure, unit-tested index math (shuffle is engine-side —
just_audio's own shuffle stays OFF); debounced persistence + cold-start restore
(`queue_persistence.dart`, tolerant of deleted tracks); and a `/debug-queue`
screen. Restore is guarded so it can never block boot.

(The `/debug-scan` and `/debug-queue` screens and the synthetic-library seeder
are permanent developer tools, not throwaways — but as of Step 4.6 the whole
Settings › Developer section and both routes are gated behind `kDebugMode`, so
they compile only into debug builds and are tree-shaken out of release/profile.)

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

**Step 3.3 — Library experience polish.** Zero-friction scanning, live
auto-detection, smart junk filtering, a unified visibility model, and liked
songs. Four staged commits:
- **Schema v6 + smart junk filter + unified visibility.** Junk filtering no
  longer hard-drops. `core`/`sources/local/junk_filter.dart` is a **pure**,
  table-driven scorer (`JunkSignals` → `scoreJunk`/`isFilterHidden`): path
  *segments* (not substrings — fixes "The Recordings" artist), recording
  extensions (amr/3gp/awb/qcp), MediaStore type flags, recording/date-stamp
  filenames, and an untagged-and-short signal, with **any real tag a strong
  protective weight**. Over-threshold tracks are **stored hidden**
  (`hiddenByFilter`), recoverable; only <5s blips are hard-dropped. Schema v5→v6
  adds `tracks.{visibility, userOverride, liked, likedAt}` (`TrackVisibility`
  enum: visible | hiddenByUser | hiddenByFilter). A shared `_visible` predicate
  filters **every** track read (album/artist/search/queue-restore/history/
  playlist counts+collage); scanner-maintenance reads stay unfiltered. The
  scanner reads existing flags before an upsert and pure `resolveVisibility`
  preserves like + hide/unhide across rescans (userOverride = permanent unhide).
- **First-run auto-scan + resume + snackbar.** No manual scan button in
  first-run: Home asks for access, then the scan auto-starts and shows friendly
  progress; content streams in progressively (chunked upserts). `app.dart` gains
  a `WidgetsBindingObserver` (resume + cold-boot incremental rescan, gated by
  pure `shouldResumeScan` >5min, persisted timestamp). A keepAlive
  `NewSongsReporter` shows a subtle "N songs added" snackbar when a rescan added
  tracks and the user is on Library (`scan_triggers.dart`).
- **Native MediaStore observer.** `MainActivity` registers a `ContentObserver`
  on the audio URI → EventChannel `com.copra.viby/media_observer` (the app's
  first platform channel; on_audio_query is pull-only). `MediaStoreObserver`
  wraps it; a pure `ScanDebouncer` (3s quiet period) coalesces a download's
  burst; keepAlive `MediaWatcher` runs a debounced incremental rescan on change.
- **Hidden-songs manager + liked songs.** Track sheet gains a heart
  (`LikeButton`, scale-pop + haptic) and "Hide song" (removes from queue,
  advancing the playing track via `QueueController.removeTrackById`). Hidden
  screen (`/settings/hidden`): two sections, per-row + all Unhide (sets
  userOverride). Tracks-tab "N hidden songs" footer. **Liked Songs** is a
  virtual collection (not a playlist): pinned card in the Playlists tab →
  `/library/liked` (newest-liked-first, Play/Shuffle, swipe-to-unlike), heart
  also in Now Playing.

251 tests green (junk scoring incl. false-positive guards, resolveVisibility
preservation, v5→v6 migration, per-DAO visibility filtering, liked round-trip,
shouldResumeScan/shouldAnnounceAdded, ScanDebouncer, removeTrackById). Debug APK
builds (native bridge compiles). **Device pass complete** (S22, Android 16):
fresh install → grant → library auto-fills with no manual scan; newly downloaded
songs appear automatically; voice recordings filtered correctly; hide/unhide
persists across rescans; Liked Songs updates instantly and persists across
restart; no playback/navigation regressions. Subsonic remains Phase 3.

## Phase 4 — Lyrics & beyond

**Step 4.1 — the lyrics system.** Synced `.lrc` + embedded lyrics with a
real-time scrolling Now Playing view. Every provenance (sidecar / embedded
synced / embedded unsynced) converges on one `Lyrics`/`LyricLine` model — the
UI never branches on source, only on `isSynced`. Five staged commits:
- **Schema v7 + LRC parser + model.** `lib/data/lyrics/`: a `lyrics` table
  (`LyricsDao`, cascade on track delete, migration + test) and the pure
  `LrcParser` (+ `decodeBytes`) — timestamp variants, multi-timestamp chorus
  expansion, `[offset:±ms]` (Wikipedia **subtract** convention — verify on
  device), metadata-ignore, malformed-skip, sort, unsynced fallback, enhanced
  word-level `<mm:ss.xx>` retained (v1 renders line-level; karaoke is v1.1).
  UTF-8 BOM strip + invalid-UTF-8 → per-line `bestDecoding` CP1256 recovery
  (reuses the mojibake decoder, never duplicated). Fixtures committed.
- **Resolution repository + embedded reader.** `LyricsRepository` runs a
  priority chain behind one `LyricsSourceResolver` (sidecar → embedded synced →
  embedded unsynced → none); first non-empty hit is parsed + drift-cached, a
  miss writes a `none` negative marker (cleared by Refresh / rescan), a flaky
  source is skipped. `id3_reader.parseLyrics` adds USLT (Latin-1 byte-preserved)
  + SYLT (ms → serialized to LRC; MPEG-frame timing rejected). The incremental
  scanner drops cached lyrics for changed files.
- **SAF sidecar grant.** A `.lrc` is a non-media file → scoped storage blocks a
  bare `File()` read on API 33+. The user grants a folder once via
  `ACTION_OPEN_DOCUMENT_TREE` (persistable tree URI, stored in the v4
  Preferences KV); `MainActivity`'s second platform channel
  (`com.copra.viby/lyrics_saf`) reads sidecars (same-dir + `/Lyrics/`) via
  `DocumentsContract`. `SafSidecarSource` overrides the Noop seam live;
  Settings › Audio has a "Lyrics folder" tile.
- **Playback binding.** `state/lyrics_providers.dart`: `currentLyricsProvider`
  rebuilds only on track change; `lyricsActiveIndexProvider` returns a narrow
  `int` (binary search) so position ticks that don't cross a line = no rebuild;
  tap-to-seek; `LyricsFollowController` (pure transition table + 4s auto-resume).
- **Now Playing UI.** A "lyrics peek" under the transport (current + dimmed
  next; hidden with no dead space when empty); `LyricsView` cross-fades
  full-screen above the artwork (artwork → corner thumb via a second overlay
  controller, no disruption to the shared-element drag). Active line: full
  opacity / primary / 1.04 scale, neighbours fade, auto-scroll to ~35% viewport;
  manual scroll pauses follow (resume pill); unsynced = static + caption; empty
  = tasteful state + "How to add lyrics" sheet (offline-pure, no online search
  in v1).

317 tests green; analyze clean; debug APK builds (native bridge compiles).
**Device pass complete** (five files: normal `.lrc`, offset `.lrc`,
embedded-USLT-only, Arabic `.lrc`, no-lyrics): tap-to-seek accuracy, the LRC
`[offset]` direction, 60fps expanded-lyrics drag on the S22, and readability
across all six themes verified. Subsonic remains Phase 4+.

**Step 4.2 — online lyrics (LRCLIB).** The final link in the resolution chain:
sidecar → embedded synced → embedded unsynced → **online**. Still **one**
`Lyrics` representation — LRCLIB synced/plain/instrumental all flow through the
same parser/model; the UI never learns a new source shape. Offline-first: every
fetch is cached permanently in drift, the feature toggles (default ON), and
airplane mode degrades silently. Three staged commits:
- **Schema v8 + repository plumbing.** `LyricsSource` gained `online` +
  `instrumental`; `LyricsLines` gained a nullable `expiresAt` (schema v8:
  `addColumn`, guarded so a `createTable` from ≤v6 doesn't double-add;
  migration + test). `LyricsRepository` distinguishes **abstain** (a source
  *throws* — transient: offline/timeout/wifi-gate → never cached) from **miss**
  (returns null — definitive → cached as a `none` negative with a 14-day
  `expiresAt` TTL, `kNegativeCacheTtl`); a `_inflight` map guards concurrent
  fetches for the same track; instrumental caches as its own marker. Local
  always beats online (chain order). Pure `query_cleanup.dart`
  (`cleanLyricsQuery`: bracket/feat/dash noise, primary-artist split, `<unknown>`
  guard) tested against real messy titles.
- **LRCLIB source + settings.** `sources/lrclib_source.dart`: `/api/get` exact
  (duration ±… is the accuracy weapon) then `/api/search` scored by
  `pickBestCandidate` (duration ≤3s + strict normalized title match + artist
  contains; ambiguity → miss, because wrong lyrics are worse than none). 8s
  timeouts, a proper lazy `User-Agent` (package_info), 404→null / transport→throw.
  Wi-Fi-only gate via a **native** `com.copra.viby/connectivity` MethodChannel
  (`ConnectivityManager`, `ACCESS_NETWORK_STATE`) — chosen over
  `connectivity_plus` (its 7.x pulls `core-ktx 1.18` → needs AGP 8.9.1; project
  is on 8.7). Settings › Audio: "Fetch lyrics online" (default ON, discloses "Sends
  song title & artist to LRCLIB") + "Wi-Fi only" (default off). Enabling clears
  the negative cache so previously-missed tracks get a shot.
- **Online UI states + manual search.** The peek shows a **shimmer** during an
  in-flight fetch (never a spinner), an "Instrumental" affordance, and a "Search
  for lyrics" affordance when empty + online-enabled (hidden when off). The
  expanded view: "Instrumental" state, an online-aware empty state (Search online
  / Enable online lyrics), a tappable **"Lyrics from LRCLIB · Wrong? Tap to
  search"** attribution, and a "Search online" overflow item. `lyrics_search_sheet.dart`
  is the editable escape hatch (query prefilled from `cleanLyricsQuery`, results
  list with durations, tap-to-apply → `cacheRaw` + re-resolve).

**Privacy / data-safety seam.** When "Fetch lyrics online" is ON, Viby sends the
**cleaned song title + artist name** (and duration/album as query hints) to
`lrclib.net` to look up lyrics. No account, device id, or other identifier is
sent; LRCLIB is anonymous. Nothing is sent for a track that already has local
lyrics, or at all when the toggle is OFF. Data-safety form: "App activity → other
(song metadata for lyrics lookup); not linked to identity; not shared onward."
**Network audit:** `lrclib.net` is the *only* runtime network destination in the
app (the queue/library/EQ are fully local; on_audio_query is pull-only). Verify
with a proxy/airplane-mode toggle-off pass that no request leaves the device once
the setting is disabled.

376 tests green; analyze clean; debug APK builds (native connectivity channel
compiles). **Device pass complete** (songs with no local lyrics fetch from
LRCLIB; airplane mode degrades silently; a mismatch is rescued by manual search;
with the toggle off no request leaves the device). Subsonic remains Phase 4+.

**Step 4.3 — delete from device.** Permanent file deletion, sitting deliberately
next to (and clearly apart from) Hide: Hide is reversible and keeps the file;
Delete is final. The wording, the colour and the confirmation flow all exist to
keep those two from being confused.
- **The platform flow is the whole design** (`sources/local/media_delete_channel.
  dart` + a fourth MethodChannel, `com.copra.viby/media_delete`). On **API 30+**
  an app may not delete another app's media: the only correct path is
  `MediaStore.createDeleteRequest` → `PendingIntent` →
  `startIntentSenderForResult`, where the **system** shows "Allow Viby to delete
  this file?" and performs the delete. So the app adds **no dialog of its own**
  there (two dialogs in a row feel broken); result: granted → clean up, denied →
  silent no-op. On **API ≤29** (minSdk 24) the system asks nothing, so the app
  deletes the row + file itself (`WRITE_EXTERNAL_STORAGE`, `maxSdkVersion=29`)
  behind *its own* destructive dialog, which names the track and points at Hide
  ("Tip: Hide removes it from your library without deleting the file"). One
  `createDeleteRequest` covers a whole batch — one system dialog for an album.
  Capability-flag pattern (rule 6): `PlatformMediaDeleter` / `NoopMediaDeleter`
  behind `MediaDeleter`, so the UI checks `capable` and never branches on
  `Platform`.
- **`LibraryMaintenance.purgeTracks(ids)` is the ONE place tracks leave the
  library** (`sources/local/library_maintenance.dart`). The user deleting a file
  and the incremental scanner finding a file gone are the same cleanup, so they
  share it — which also makes them safe to *race* (deleting a file wakes the
  MediaStore observer, whose rescan diff names the same ids; purging ids that are
  already gone is a no-op). FKs cascade history/cache/lyrics; the purge covers
  what they don't: playlist entries (plain key → dropped + positions
  re-compacted), album track counts (recomputed; emptied albums deleted),
  artists with no tracks *and* no albums, and artwork files + cached palette
  seeds no surviving row still points at. Liked/visibility are columns and die
  with the row. DB work is one transaction; art files are deleted after it
  commits, and a stuck file never fails the purge.
- **Nothing in the DB changes until the files are confirmed gone**
  (`state/delete_actions.dart`): denied → no-op, failed (read-only card, locked
  file) → honest snackbar and the library is untouched, so a song is never shown
  as deleted while the file is still there. On success the tracks leave the queue
  (`removeTrackById` → a playing copy advances; **removing the only item now
  calls `clearQueue`**, so playback stops and the notification is torn down
  instead of leaving a stale one).
- **Source guard** (pure `sources/local/delete_targets.dart`): only `local`
  tracks whose id maps back to a real MediaStore row are deletable —
  `subsonic:` pointers and `local:synthetic:` seed rows can never reach the
  platform call. The `source` enum earns its keep.
- **Entry points, and only these:** the track long-press sheet (a visually
  separated, error-coloured "Delete from device / Removes the file permanently"
  row below Hide) and the album-detail **overflow** ("Delete album from device").
  Never in the Now Playing transport or anywhere a mis-tap is cheap. Success
  says "Deleted 'Title'" with **no undo** — the file is gone and a fake undo
  would be a lie. That is what Hide is for. (Multi-select is not wired: there is
  no existing multi-select pattern to hang it on, so batch = album-level.)

**Step 4.3a — ghost albums/artists (fixed after the device pass).** Junk-filtered
recordings are *hidden, not dropped* (3.3), so the album/artist rows the scanner
wrote for them outlived their tracks and surfaced as empty cards ("Alarms",
"Call", an "Unknown artist" full of nothing). Browsing now filters them the way it
filters tracks: **an album is in the library iff a visible track points at it; an
artist iff they have a visible track** — a correlated `EXISTS` (short-circuits on
the first hit, rides `idx_tracks_album` / `idx_tracks_artist`) on the albums grid,
`watchAllAlbums`, the artists list and artist-detail's album list.
`watchArtist(id)` stays **unfiltered** on purpose: it resolves a name for a row
already on screen (the Hidden-songs screen depends on it) — which is precisely why
the ghost rows must keep existing. Counts are visible-only too, so an album card's
number matches the list you get when you open it: hide/unhide recomputes the
album inside the DAO transaction, and every scan ends with a whole-library
recount (`recomputeAllAlbumTrackCounts`), self-healing albums an incremental scan
never touched. Measured at 10k: albums grid 58ms, artists 6ms, full recount 34ms.
**Device pass complete.**

403 tests green (added: the purge cascade matrix — playlist re-compaction, empty
album/artist cleanup, artwork + palette orphan eviction, art-still-in-use kept,
hidden rows purgeable, a failed eviction not failing the purge; idempotency incl.
two concurrent purges of the same id; queue removal incl. the only-item stop;
the source guard; channel outcome mapping + one-request batching; the sheet's
destructive affordance) — **410 with 4.3a** (ghost-album/artist exclusion, count
correctness, the live hide→vanish/unhide→return round-trip through the real watch
stream, Hidden-songs screen unaffected). Analyze clean; debug APK builds (the
delete channel compiles). **Device pass complete** (S22, Android 16): single
delete → system dialog, file gone, vanishes from library/queue/playlist instantly;
the playing track advances cleanly; album batch-delete; denying the dialog changes
nothing; an album's last track takes the album with it, no orphan art.

**Step 4.4 — the brand mark.** The new app icon, deconstructed from the master
tile (`assets-design/adio_logo1.jpg` — a *presentation mockup*: the mark on a
charcoal tile, on a light page, with a drop shadow; never shipped whole).
`tools/gen_icons.py` regenerates every piece and is the source of truth:
- **The glyph is a traced vector, not an upscaled raster.** The source mark is
  ~250px, so a PNG-per-density foreground would be visibly soft at xxxhdpi.
  Pipeline: isolate the tile → sample its true charcoal (**#2B2B2B**) → isolate
  the glyph → supersample the *grayscale* (so the traced boundary lands on the
  antialiased edge, not a threshold staircase) → contour-trace → RDP simplify
  (keeps nodes where curvature demands them — the tapered tips — and drops them
  along lazy arcs) → Catmull-Rom cubics. Fidelity is **measured**: `--check`
  prints the IoU against the source mask (**0.9844**; the residual is the
  antialiased edge). The vector also buys the Android 13+ **monochrome/themed**
  layer and the notification silhouette for free.
- **The 66dp safe zone is a LIMIT, not a target.** Sized to 66 the glyph fills
  92% of the 72dp visible area — far heavier than the master, where the mark is
  70.6% of the tile. It's scaled to that same share of the *visible* area
  (~51dp): matches the brand's optical weight and clears circle / squircle /
  rounded-square masks with margin. The **splash reuses the adaptive foreground**
  (at 47% of its viewport it also clears the splash's inner-⅔ circle) — one
  drawable, one safe zone, nothing to keep in sync.
- **Corner radius is measured off the tile's top row (0.187).** An area-based
  estimate returns 0.32 because it counts the mockup's drop shadow.
- `ic_stat_viby` is the same glyph as a flat white silhouette: Android renders
  small-icons from the **alpha only** and re-tints them, so a filled tile would
  show as a solid blob. Play Store master (`assets-design/store/`) is a
  **full-bleed square with no alpha** — Play applies its own corner mask, so a
  pre-rounded tile would be double-rounded. Splash + adaptive background use the
  sampled charcoal (identical light/dark → still no white flash on cold start).
- In-app, `ui/widgets/viby_mark.dart` (tintable silhouette asset) replaces the
  stock Material icons in the Home welcome state and About. (There was no in-app
  waveform mark to sweep — the old waveform only ever existed in the launcher
  XML.) **Device pass complete** (S22): two launcher shapes, themed icon, splash,
  notification icon.

**Step 4.5 — audiophile finesse.** Individually small, together the "this app
respects music" layer. All the policy is pure and unit-tested; the handler obeys.
- **ONE VOLUME AUTHORITY** (`audio/volume_mixer.dart`). Gain (ReplayGain), duck
  (interruption) and fade (resume / sleep) are three factors multiplied by
  `mixVolume()` — the only function allowed to compute a volume. Load-bearing:
  the interruption handler used to call `setVolume(0.3)` / `setVolume(1.0)`
  directly, which would have discarded a track's normalized level and silently
  un-normalized it. It's also why the resume fade ramps **to the track's
  ReplayGain level**, not to full scale. **EQ composes by construction** (the
  equalizer is in the just_audio `AudioPipeline`; this scales output volume).
- **Volume normalization (ReplayGain)** — `audio/replay_gain.dart` +
  **schema v9** (`rgTrackGainDb/rgTrackPeak/rgAlbumGainDb/rgAlbumPeak` +
  `rgScanned`; migration + test). Tags are read with the project's **own
  dependency-free `id3_reader`, NOT `audiotags`** (removed for breaking the AGP 8
  build): `parseReplayGain` reads `TXXX` (what loudgain/foobar2000/mp3gain write —
  case-insensitive, tolerating `-7.35 dB` / bare numbers / comma decimals) with
  `RVA2` as fallback. Reading is a **post-scan phase** (`ScanPhase.replayGain`) —
  it's the only part of scanning that must open *every* file, so it runs after the
  library is browsable. `rgScanned` keeps "untagged" distinct from "not looked at",
  so each file is read exactly once (a changed file re-arms it, like the lyrics
  drop); the scanner's normal upsert omits the columns, so a rescan preserves them.
  Policy: **untagged files play at 1.0 with no pre-amp** (a fabricated level is
  worse than none); album mode falls back to track gain; clip protection caps at
  `1/peak`; the scalar clamps to **[0,1]** because the platform volume is an
  *attenuator* — normalization pulls loud masters *down* to the reference, which
  is exactly how a loud/quiet pair evens out. Settings › Playback › Volume
  normalization (mode / pre-amp −6..+6 dB / prevent clipping).
- **Sleep timer** (`audio/sleep_timer.dart`) — 15/30/45/60 min, end-of-track,
  end-of-queue. Lives in the **audio layer**, so it survives a disposed UI and a
  backgrounded app; `SleepAfter` anchors to an **absolute deadline** (not a
  decremented counter), so a starved background process still fires on time. The
  fade-out (last 10s, never a hard stop) is driven from `remaining` every tick, so
  a seek during end-of-track can't desync it. End-of-queue needs the engine's
  repeat-aware `hasNext`, which the player can't compute — the queue pushes it
  down through the sink. Countdown chip in Now Playing (tap → extend / cancel).
- **Speed** 0.5–2.0x, pitch preserved; chip when ≠ 1x. **Session-only, and that's
  deliberate**: a persisted 1.5x is a trap you set for an audiobook and rediscover
  a week later as "music sounds subtly wrong", with no way to connect it to a
  setting you forgot.
- **Skip silence** (Android) and **resume fade-in** (300ms, 0→level, kills the
  headphone blast; a track *start* is never faded — it should begin at its level,
  not swell into it).
- Playback settings live in the **v4 preferences KV store** (no migration) and are
  hydrated **at app start**, not lazily from Settings, so they apply to the first
  track played.

453 tests green (added: RG scalar math incl. peak/pre-amp/clamp + the untagged
rule, fade×RG composition, the sleep state machine incl. end-of-track/end-of-queue
and the absolute-deadline background case, TXXX/RVA2 parsing, the scan phase's
read-once behaviour, v8→v9 migration). Analyze clean. **Device pass complete**
(S22): RG evens out a loud/quiet pair, the sleep timer fades and stops while
backgrounded, the speed chip appears and resets on restart. Subsonic remains
Phase 4+.

**Step 4.6 — pre-launch bug pass.** Four items, the first two root-caused (no
symptom patches):
- **Silent-playback bug (root cause: the resume fade awaited just_audio's
  `play()`).** just_audio's `AudioPlayer.play()` Future completes not when
  playback *starts* but at the next pause/stop (its documented behaviour). The
  handler scheduled the resume ramp *after* `await _player.play()`, so on a real
  resume the ramp never ran during playback and the fade envelope was stranded at
  0 — audible position, no sound; rapid toggling raced past it (already-`playing`
  → `play()` returns immediately → ramp ran), which is why fast pause-play stayed
  audible. Fix: the fade is now a pure, clock-injected state machine
  (`audio/fade_envelope.dart`, `FadeEnvelope`) advanced by the handler's own
  ticker, never coupled to the play Future. Its invariant — **any `resume` +
  enough `advance` lands at exactly 1.0** — means no pause/play interleaving can
  strand it low; pause cancels the ramp, resume always re-targets full from the
  current value, and the fade factor still multiplies the ReplayGain scalar (so
  the target is the RG level, not a hard 1.0). A fresh queue snaps the envelope to
  full (an unfaded start). Tested with a fake clock incl. a 2000-trial final-volume
  invariant property test.
- **Drag-to-minimize regression (two root causes in `player_overlay.dart`).**
  (1) `_onDragEnd` derived the settle `origin` from `_c.value` *at release*
  instead of where the drag *began*; once a full→mini drag crossed the midpoint
  the origin flipped to 0 and the "commit to the opposite end" branch sent the
  panel back *up*. Now the origin is captured in `_onDragStart` (`_dragOrigin`).
  (2) The shared-artwork layer gated its vertical-drag callbacks on
  `artInteractive`, which flips false within ~14px of a downward drag (as `t`
  drops below 0.98) — nulling the callbacks disposed the active drag recognizer
  mid-gesture, stranding a drag *begun on the artwork* near full. The callbacks
  are now attached unconditionally (the `IgnorePointer` still blocks a *new* drag
  when not at rest). A widget test drives a single moderate-velocity drag from
  both the artwork and a bare panel area and asserts one-drag collapse; each fix
  was verified load-bearing by reverting it.
- **Corner actions polish.** All four (heart · A-B · queue · more) bumped 20→24dp
  in ≥44dp touch boxes and unified as one plain-glyph family. The A-B action's
  `repeat_on_outlined` (a baked-in rounded-square background) is replaced by a
  hand-drawn glyph — two endpoint markers + a loop arc with a return arrowhead
  (`ui/player/ab_repeat_icon.dart`, a `CustomPainter` at the Material ~2dp
  round-cap weight); active state is color+fill only (secondary → primary).
- **Developer section gated behind `kDebugMode`.** The Settings › Developer
  section (scan/queue debug + synthetic seeder) and both `/settings/debug-*`
  routes now sit behind the literal `kDebugMode` const (was `!kReleaseMode`, which
  still shipped them in profile), so release *and* profile dead-code-eliminate and
  tree-shake them out entirely. A route-table test asserts the debug routes are
  present **iff** `kDebugMode` (the gating contract). The debug screens/seeder are
  permanent dev tools, not throwaways.
- **Artist artwork never rendered (root cause: a drift query threw for every
  artist).** The derived-portrait feature (an artist's picture borrowed from
  their most-played album, letter avatar as last resort) showed letter
  placeholders everywhere. Root cause found by inspecting the live on-device DB
  (the data was healthy — Travis Scott had 3 albums with art) then reproducing in
  a DAO test: `LibraryDao.artistArtCandidates` read its `trackCount`/`playCount`
  aggregate columns via `r.read(...)` **without `..addColumns([...])`**, which
  drift rejects ("result set has no column for that expression") — so the query
  threw for *every* artist, the `artistArtwork` provider became an AsyncError, and
  `ArtistArt` fell back to the letter avatar universally. One-line fix: add the
  aggregates to the statement (every other aggregate query in the DAO already
  did). The pure picker already falls through play-count → track-count →
  alphabetical → (only then) null, so zero-play artists still get real art.
- **Artist-detail palette header.** The artist-detail header now paints a
  vertical gradient tinted by the portrait's own colour (~40% at the top, fading
  into `surface` behind the name), reusing the **existing** dynamic-theme
  extraction pipeline + LRU/drift palette cache via a new `artistSeedProvider`
  (no second extractor). It's a contextual header treatment, not a whole-screen
  recolour (per the dynamic-colour-is-contextual rule), and lives in the
  `FlexibleSpaceBar` background so it collapses with the header. Null seed (no
  art / near-monochrome) → the calm surface gradient; the bottom stop stays pure
  `surface` so text contrast holds.

512 tests green (added: the `FadeEnvelope` interruption + invariant property
tests, the single-drag full→mini regression test from artwork + bare panel, the
corner-action family/24dp/active-colour test, the `kDebugMode` route-gate test,
the `artistArtCandidates` aggregate/fall-through tests, and the `artistSeed`
cache-reuse + rescan-invalidation tests). Analyze clean. **Device pass**: silent
playback ✓ and one-swipe minimize ✓ verified on S22 (the bug was also confirmed
first-hand by pulling the on-device DB). Still pending: artist artwork + tinted
header on device; pause/play torture at every spacing incl. inside the first
300ms; minimize from ten start points; icon coherence at arm's length; sideload
the release APK and confirm Settings has no Developer section. Subsonic remains
Phase 4+.
