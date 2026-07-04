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

---

## Current phase

**Phase 0 — Scaffold.** Structure, config, and conventions only; no features.
The app boots to a placeholder `HomeScreen` via go_router. Next phase: the
`Track` model, the drift database, and the `player_service.dart` facade.
