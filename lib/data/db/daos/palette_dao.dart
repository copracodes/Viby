import 'package:drift/drift.dart';

import '../tables.dart';
import '../viby_database.dart';

part 'palette_dao.g.dart';

/// Persists the extracted dominant seed colour per artwork so dynamic theming
/// is instant on cold start (no palette re-extraction). Seeds are stored as
/// packed ARGB ints.
@DriftAccessor(tables: <Type>[ArtworkPalettes])
class PaletteDao extends DatabaseAccessor<VibyDatabase> with _$PaletteDaoMixin {
  PaletteDao(super.db);

  /// The cached seed for [artworkKey], or null if not computed yet.
  Future<int?> getSeed(String artworkKey) async {
    final ArtworkPaletteRow? row = await (select(artworkPalettes)
          ..where((t) => t.artworkKey.equals(artworkKey)))
        .getSingleOrNull();
    return row?.seedColor;
  }

  /// Caches [seedColor] (packed ARGB) for [artworkKey], overwriting any prior.
  Future<void> putSeed(String artworkKey, int seedColor) {
    return into(artworkPalettes).insertOnConflictUpdate(
      ArtworkPalettesCompanion.insert(
        artworkKey: artworkKey,
        seedColor: seedColor,
      ),
    );
  }

  /// Evicts cached seeds whose artwork is gone (the art file was deleted with
  /// the last track of an album). Idempotent.
  Future<int> deleteSeeds(List<String> artworkKeys) {
    if (artworkKeys.isEmpty) return Future<int>.value(0);
    return (delete(artworkPalettes)..where((t) => t.artworkKey.isIn(artworkKeys)))
        .go();
  }
}
