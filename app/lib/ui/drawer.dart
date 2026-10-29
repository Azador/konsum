import 'package:flutter/material.dart';

import '../state/group_session.dart';
import 'articles_page.dart';
import 'categories_page.dart';
import 'dialogs.dart';
import 'group_page.dart';
import 'scope.dart';
import 'shops_page.dart';

/// Seitenmenü: Gruppen mit ihren Listen und Verwaltung.
class GroupDrawer extends StatelessWidget {
  const GroupDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final current = app.currentGroup;
    return NavigationDrawer(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
          child: Text('Konsum', style: TextStyle(fontSize: 22)),
        ),
        for (final g in app.groups) ...[
          ListTile(
            contentPadding: const EdgeInsets.only(left: 28, right: 12),
            title: Text(
              g.info.name,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            leading: Icon(_statusIcon(g.status), size: 20),
            trailing: IconButton(
              tooltip: 'Gruppe verwalten',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => _push(context, GroupPage(session: g)),
            ),
          ),
          for (final l in g.group.lists)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 44, right: 16),
              leading: const Icon(Icons.checklist),
              title: Text(l.name),
              selected: g == current && l.id == app.currentListId,
              onTap: () {
                app.selectList(g, l.id);
                Navigator.pop(context);
              },
            ),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 44, right: 16),
            leading: const Icon(Icons.add),
            title: const Text('Neue Liste'),
            onTap: () async {
              final name = await promptText(context, title: 'Neue Liste');
              if (name != null) app.createList(g, name);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const Divider(indent: 28, endIndent: 28),
        ],
        ListTile(
          contentPadding: const EdgeInsets.only(left: 28, right: 16),
          leading: const Icon(Icons.group_add_outlined),
          title: const Text('Neue Gruppe'),
          onTap: () async {
            final name = await promptText(context, title: 'Neue Gruppe');
            if (name != null) {
              final g = await app.createGroup(name);
              app.createList(g, 'Einkaufsliste');
            }
            if (context.mounted) Navigator.pop(context);
          },
        ),
        if (current != null) ...[
          const Divider(indent: 28, endIndent: 28),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 16, 4),
            child: Text(
              current.info.name,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 28, right: 16),
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Artikel'),
            onTap: () => _push(context, ArticlesPage(session: current)),
          ),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 28, right: 16),
            leading: const Icon(Icons.category_outlined),
            title: const Text('Kategorien'),
            onTap: () => _push(context, CategoriesPage(session: current)),
          ),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 28, right: 16),
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Läden'),
            onTap: () => _push(context, ShopsPage(session: current)),
          ),
        ],
      ],
    );
  }

  static IconData _statusIcon(SyncStatus s) => switch (s) {
    SyncStatus.local => Icons.phone_android,
    SyncStatus.offline => Icons.cloud_off,
    SyncStatus.pending => Icons.cloud_upload_outlined,
    SyncStatus.synced => Icons.cloud_done_outlined,
  };

  static void _push(BuildContext context, Widget page) {
    final navigator = Navigator.of(context)..pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }
}
