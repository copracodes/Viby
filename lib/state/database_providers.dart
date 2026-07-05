import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/db/viby_database.dart';

part 'database_providers.g.dart';

/// App-wide database handle. Kept alive for the whole session and closed on
/// dispose.
@Riverpod(keepAlive: true)
VibyDatabase vibyDatabase(Ref ref) {
  final VibyDatabase db = VibyDatabase();
  ref.onDispose(db.close);
  return db;
}
