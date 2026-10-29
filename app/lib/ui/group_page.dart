import 'package:flutter/material.dart';

import '../state/group_session.dart';
import 'account_page.dart';
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
          _MatrixSection(session: session),
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

/// Teilen über Matrix, Mitglieder und Einladungen.
class _MatrixSection extends StatefulWidget {
  const _MatrixSection({required this.session});

  final GroupSession session;

  @override
  State<_MatrixSection> createState() => _MatrixSectionState();
}

class _MatrixSectionState extends State<_MatrixSection> {
  Future<List<String>>? _members;

  @override
  Widget build(BuildContext context) {
    final matrix = MatrixScope.maybeOf(context);
    if (matrix == null) return const SizedBox.shrink();
    final backend = widget.session.info.backend;

    if (!matrix.isLoggedIn) {
      return ListTile(
        leading: const Icon(Icons.share_outlined),
        title: const Text('Teilen'),
        subtitle: const Text('Zum Teilen erst mit Matrix anmelden'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const AccountPage()),
        ),
      );
    }
    if (backend == null) {
      return ListTile(
        leading: const Icon(Icons.share_outlined),
        title: const Text('Über Matrix teilen'),
        subtitle: Text(
          'Legt einen Matrix-Raum für die Gruppe an. Danach kannst du '
          'andere einladen.'
          '${matrix.encryptionEnabled ? ' Der Raum wird verschlüsselt.' : ''}',
        ),
        enabled: !matrix.busy,
        onTap: () => matrix.share(widget.session),
      );
    }
    _members ??= matrix.members(widget.session);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.tag),
          title: const Text('Matrix-Raum'),
          subtitle: SelectableText('${backend['roomId']}'),
        ),
        if (matrix.isEncrypted(widget.session) case final encrypted?)
          ListTile(
            leading: Icon(
              encrypted ? Icons.lock_outline : Icons.lock_open_outlined,
            ),
            title: Text(encrypted ? 'Verschlüsselt' : 'Nicht verschlüsselt'),
            subtitle: Text(
              encrypted
                  ? 'Nur die Geräte der Mitglieder können die Liste lesen.'
                  : 'Der Matrix-Server kann die Liste lesen.',
            ),
          ),
        FutureBuilder(
          future: _members,
          builder: (context, snapshot) => ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Mitglieder'),
            subtitle: Text(
              snapshot.hasData
                  ? snapshot.data!.join('\n')
                  : snapshot.hasError
                  ? 'Nicht abrufbar'
                  : '…',
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.person_add_alt),
          title: const Text('Einladen'),
          enabled: !matrix.busy,
          onTap: () async {
            final userId = await promptText(
              context,
              title: 'In die Gruppe einladen',
              label: 'Matrix-ID, z. B. @name:beispiel.de',
              confirm: 'Einladen',
            );
            if (userId != null && await matrix.invite(widget.session, userId)) {
              setState(() => _members = matrix.members(widget.session));
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.exit_to_app),
          title: const Text('Gruppe verlassen'),
          enabled: !matrix.busy,
          onTap: () async {
            if (await confirm(
                  context,
                  title: 'Gruppe verlassen?',
                  message:
                      'Du verlässt den Matrix-Raum, die lokalen Daten '
                      'werden gelöscht. Wieder dabei bist du nur mit einer '
                      'neuen Einladung.',
                  action: 'Verlassen',
                ) &&
                await matrix.leave(widget.session) &&
                context.mounted) {
              Navigator.pop(context);
            }
          },
        ),
        if (matrix.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              matrix.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
