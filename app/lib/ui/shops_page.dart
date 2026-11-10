import 'package:flutter/material.dart';
import 'package:konsum_core/konsum_core.dart';

import '../state/group_session.dart';
import 'dialogs.dart';
import 'scope.dart';

class ShopsPage extends StatelessWidget {
  const ShopsPage({super.key, required this.session});

  final GroupSession session;

  void _open(BuildContext context, String shopId) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ShopPage(session: session, shopId: shopId),
    ),
  );

  @override
  Widget build(BuildContext context) {
    AppScope.of(context);
    final group = session.group;
    return Scaffold(
      appBar: AppBar(title: const Text('Läden')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Neuer Laden',
        child: const Icon(Icons.add),
        onPressed: () async {
          final name = await promptText(context, title: 'Neuer Laden');
          if (name == null) return;
          final r = group.createShop(name);
          session.apply(r.changes);
          // Startreihenfolge: alle Kategorien alphabetisch.
          session.apply(
            group.updateShop(
              r.id,
              categoryOrder: [for (final c in group.categories) c.id],
            ),
          );
          if (context.mounted) _open(context, r.id);
        },
      ),
      body: group.shops.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Lege Läden an, um die Liste in der Reihenfolge des '
                  'jeweiligen Ladens zu sortieren.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final s in group.shops)
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(s.name),
                    onTap: () => _open(context, s.id),
                  ),
              ],
            ),
    );
  }
}

/// Ein Laden: Reihenfolge der Kategorien per Ziehen festlegen.
class ShopPage extends StatelessWidget {
  const ShopPage({super.key, required this.session, required this.shopId});

  final GroupSession session;
  final String shopId;

  @override
  Widget build(BuildContext context) {
    AppScope.of(context);
    final group = session.group;
    final shop = group.shop(shopId);
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Laden wurde gelöscht.')),
      );
    }
    final order = _fullOrder(shop, group.categories);
    final names = {for (final c in group.categories) c.id: c.name};

    return Scaffold(
      appBar: AppBar(
        title: Text(shop.name),
        actions: [
          IconButton(
            tooltip: 'Umbenennen',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final name = await promptText(
                context,
                title: 'Laden umbenennen',
                initial: shop.name,
              );
              if (name != null) {
                session.apply(group.updateShop(shopId, name: name));
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'prices' &&
                  await confirm(
                    context,
                    title: 'Preishistorie von ${shop.name} löschen?',
                  )) {
                session.apply(group.deletePriceHistory(shopId: shopId));
              } else if (v == 'delete' &&
                  context.mounted &&
                  await confirm(
                    context,
                    title: '${shop.name} löschen?',
                    message: 'Preise aus diesem Laden bleiben in der Historie.',
                  )) {
                session.apply(group.deleteShop(shopId));
                if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'prices',
                child: Text('Preishistorie löschen'),
              ),
              PopupMenuItem(value: 'delete', child: Text('Laden löschen')),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Reihenfolge der Kategorien im Laden. Zum Verschieben am Griff '
              'ziehen oder die Zeile kurz halten.',
            ),
          ),
          Expanded(
            child: ReorderableListView(
              // Ganze Zeile: nach kurzem Halten ziehen (sonst wird gescrollt).
              // Griff am Zeilenanfang: sofort ziehen.
              buildDefaultDragHandles: false,
              // Anders als ListView rückt ReorderableListView nicht von
              // selbst um die Systemleiste ein; ohne das verdeckt die
              // Android-Navigationsleiste die letzten Kategorien.
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              onReorderItem: (from, to) {
                final next = [...order];
                next.insert(to, next.removeAt(from));
                session.apply(group.updateShop(shopId, categoryOrder: next));
              },
              children: [
                for (final (i, id) in order.indexed)
                  ReorderableDelayedDragStartListener(
                    key: ValueKey(id),
                    index: i,
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(right: 16),
                      leading: ReorderableDragStartListener(
                        index: i,
                        // Transparente Fläche, damit die ganze Griffbreite
                        // reagiert und nicht nur das Symbol.
                        child: const ColoredBox(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: 56,
                            height: 48,
                            child: Icon(Icons.drag_indicator),
                          ),
                        ),
                      ),
                      title: Text(names[id] ?? ''),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Gespeicherte Reihenfolge, ergänzt um später angelegte Kategorien.
  static List<String> _fullOrder(Shop shop, List<Category> categories) {
    final existing = {for (final c in categories) c.id};
    final order = shop.categoryOrder.where(existing.contains).toList();
    order.addAll(existing.where((id) => !order.contains(id)));
    return order;
  }
}
