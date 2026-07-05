import 'package:drift/drift.dart';

import '../tables.dart';
import '../viby_database.dart';

part 'server_dao.g.dart';

/// CRUD for Subsonic server rows. Passwords are not stored here — see
/// [Servers].
@DriftAccessor(tables: <Type>[Servers])
class ServerDao extends DatabaseAccessor<VibyDatabase> with _$ServerDaoMixin {
  ServerDao(super.db);

  Stream<List<ServerRow>> watchServers() {
    return (select(servers)
          ..orderBy(<OrderClauseGenerator<$ServersTable>>[
            (t) => OrderingTerm(expression: t.name.lower()),
          ]))
        .watch();
  }

  Future<ServerRow?> getServer(String id) {
    return (select(servers)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> upsertServer(ServersCompanion server) {
    return into(servers).insertOnConflictUpdate(server);
  }

  Future<void> deleteServer(String id) async {
    await (delete(servers)..where((t) => t.id.equals(id))).go();
  }
}
