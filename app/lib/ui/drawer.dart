import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/group_session.dart';
import 'account_page.dart';
import 'articles_page.dart';
import 'categories_page.dart';
import 'dialogs.dart';
import 'group_page.dart';
import 'purchases_page.dart';
import 'scope.dart';
import 'shops_page.dart';
import 'theme.dart';

/// Seitenmenü: Gruppen mit ihren Listen und Verwaltung.
class GroupDrawer extends StatelessWidget {
  const GroupDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final current = app.currentGroup;
    final matrix = MatrixScope.maybeOf(context);
    return NavigationDrawer(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
          child: Text('Konsum', style: TextStyle(fontSize: 22)),
        ),
        for (final invite in matrix?.invitations ?? const [])
          ListTile(
            contentPadding: const EdgeInsets.only(left: 28, right: 12),
            leading: const Icon(Icons.mail_outline),
            title: Text(invite.name),
            subtitle: const Text('Einladung'),
            trailing: TextButton(
              onPressed: matrix!.busy ? null : () => matrix.join(invite),
              child: const Text('Beitreten'),
            ),
          ),
        for (final g in app.groups) ...[
          ListTile(
            contentPadding: const EdgeInsets.only(left: 28, right: 12),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    g.info.name,
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _ColorDot(app.colorFor(g)),
              ],
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
          ListTile(
            contentPadding: const EdgeInsets.only(left: 28, right: 16),
            leading: const Icon(Icons.history),
            title: const Text('Käufe'),
            onTap: () => _push(context, PurchasesPage(session: current)),
          ),
        ],
        if (matrix != null) ...[
          const Divider(indent: 28, endIndent: 28),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 28, right: 16),
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Matrix-Konto'),
            subtitle: Text(matrix.userId ?? 'Nicht angemeldet'),
            onTap: () => _push(context, const AccountPage()),
          ),
        ],
        const Divider(indent: 28, endIndent: 28),
        SwitchListTile(
          contentPadding: const EdgeInsets.only(left: 28, right: 16),
          secondary: const Icon(Icons.autorenew),
          title: const Text('Wiederkehrende Artikel'),
          subtitle: const Text(
            'Menge nach Verbrauch, fällige Artikel auf die Liste · '
            'nur auf diesem Gerät',
          ),
          value: app.automatic,
          onChanged: (on) => app.automatic = on,
        ),
        ListTile(
          contentPadding: const EdgeInsets.only(left: 28, right: 16),
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Datenschutz'),
          onTap: () async {
            // Statuszeile vorher holen: Das Menü ist danach geschlossen.
            final status = app.status;
            Navigator.pop(context);
            final ok = await launchUrl(
              privacyPolicy,
              mode: LaunchMode.externalApplication,
            );
            if (!ok) status.show('Browser konnte nicht geöffnet werden');
          },
        ),
      ],
    );
  }

  /// Für Google Play muss die Erklärung auch in der App verlinkt sein.
  static final privacyPolicy = Uri.parse(
    'https://konsum.azadoro.de/datenschutz.html',
  );

  static IconData _statusIcon(SyncStatus s) => switch (s) {
    SyncStatus.local => Icons.phone_android,
    SyncStatus.offline => Icons.cloud_off,
    SyncStatus.resyncing => Icons.cloud_sync_outlined,
    SyncStatus.pending => Icons.cloud_upload_outlined,
    SyncStatus.synced => Icons.cloud_done_outlined,
  };

  static void _push(BuildContext context, Widget page) {
    final navigator = Navigator.of(context)..pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

/// Farbe des Farbschemas einer Gruppe, wie sie in der App erscheint.
class _ColorDot extends StatelessWidget {
  const _ColorDot(this.argb);

  final int? argb;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: buildTheme(
        argb == null ? null : Color(argb!),
        Theme.of(context).brightness,
      ).colorScheme.primary,
    ),
  );
}
