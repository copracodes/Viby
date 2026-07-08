import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/cache_dao.dart';
import 'daos/history_dao.dart';
import 'daos/library_dao.dart';
import 'daos/palette_dao.dart';
import 'daos/playlist_dao.dart';
import 'daos/preferences_dao.dart';
import 'daos/queue_dao.dart';
import 'daos/search_dao.dart';
import 'daos/server_dao.dart';
import 'tables.dart';

part 'viby_database.g.dart';

/// The Viby drift database — the single source of truth for the local library,
/// playlists, history, offline cache and restorable queue.
///
/// Reads are reactive: UI-facing queries return `watch()` streams (see the
/// DAOs). Writes that touch multiple rows run in transactions/batches.
@DriftDatabase(
  tables: <Type>[
    Tracks,
    Albums,
    Artists,
    Playlists,
    PlaylistEntries,
    PlayHistory,
    Servers,
    CacheEntries,
    QueueState,
    Searches,
    ArtworkPalettes,
    Preferences,
  ],
  daos: <Type>[
    LibraryDao,
    PlaylistDao,
    HistoryDao,
    QueueDao,
    CacheDao,
    ServerDao,
    SearchDao,
    PaletteDao,
    PreferencesDao,
  ],
)
class VibyDatabase extends _$VibyDatabase {
  /// Opens the on-device database (app documents dir).
  VibyDatabase() : super(_openConnection());

  /// Opens against a caller-provided executor — used by tests with
  /// `NativeDatabase.memory()`.
  VibyDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // Case-insensitive index for title search/sort. Not expressible via
      // @TableIndex (which has no per-column collation), so it's raw SQL.
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tracks_title_nocase '
        'ON tracks (title COLLATE NOCASE)',
      );
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // SCHEMA-CHANGE POLICY: bump `schemaVersion`, add an `if (from < N)`
      // block here performing the incremental migration, and add a matching
      // migration test. Never edit an existing version's shape in place.
      // (Mirrored in CLAUDE.md.)

      // v1 → v2: recent-searches table.
      if (from < 2) {
        await m.createTable(searches);
      }
      // v2 → v3: per-track `playable` flag (defaults true for existing rows).
      if (from < 3) {
        await m.addColumn(tracks, tracks.playable);
      }
      // v3 → v4: artwork seed-colour cache + generic preferences KV store
      // (album-art dynamic theming).
      if (from < 4) {
        await m.createTable(artworkPalettes);
        await m.createTable(preferences);
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // Enforce foreign keys (off by default in SQLite) so the cascade
      // deletes declared on the tables actually fire.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File(p.join(dir.path, 'viby.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
