import 'package:flutter/material.dart';

import '../state/group_session.dart';
import 'dialogs.dart';
import 'scope.dart';

/// Einstellungen einer Gruppe.
class GroupPage extends StatelessWidget {
  const GroupPage({super.key, required this.session});

  final GroupSession session;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final group = session.group;
    final status = switch (session.status) {
      SyncStatus.local => 'Nur auf diesem Gerät',
      SyncStatus.offline => 'Offline – Änderungen werden später übertragen',
      SyncStatus.pending => 'Wird synchronisiert …',
      SyncStatus.synced => 'Synchronisiert',
    };
    return Scaffold(
      appBar: AppBar(title: Text(session.info.name)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Name'),
            subtitle: Text(session.info.name),
            onTap: () async {
              final name = await promptText(
                context,
                title: 'Gruppe umbenennen',
                initial: session.info.name,
              );
              if (name != null) app.renameGroup(session, name);
            },
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Synchronisation'),
            subtitle: Text(status),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.price_change_outlined),
            title: const Text('Gesamte Preishistorie löschen'),
            subtitle: Text('${group.priceHistory().length} Einträge'),
            onTap: () async {
              if (await confirm(
                context,
                title: 'Gesamte Preishistorie löschen?',
                message:
                    'Alle gespeicherten Preise der Gruppe werden für '
                    'alle Mitglieder gelöscht.',
              )) {
                session.apply(group.deletePriceHistory());
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Gruppe von diesem Gerät entfernen'),
            onTap: () async {
              if (await confirm(
                context,
                title: '„${session.info.name}“ entfernen?',
                message: session.info.backend == null
                    ? 'Die Gruppe existiert nur auf diesem Gerät, ihre Daten '
                          'gehen verloren.'
                    : 'Die lokalen Daten werden gelöscht. Die Gruppe bleibt '
                          'für die anderen Mitglieder erhalten.',
                action: 'Entfernen',
              )) {
                await app.removeGroup(session);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}
