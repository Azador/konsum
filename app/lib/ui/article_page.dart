import 'package:flutter/material.dart';

import '../state/group_session.dart';
import 'dialogs.dart';
import 'format.dart';
import 'scope.dart';
import 'unit_field.dart';

/// Einzelner Artikel: Name, Kategorie, Standardeinheit, Barcodes,
/// Preishistorie, endgültiges Löschen.
class ArticlePage extends StatelessWidget {
  const ArticlePage({
    super.key,
    required this.session,
    required this.articleId,
  });

  final GroupSession session;
  final String articleId;

  @override
  Widget build(BuildContext context) {
    AppScope.of(context);
    final group = session.group;
    final article = group.article(articleId);
    if (article == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Artikel wurde gelöscht.')),
      );
    }
    final prices = group.priceHistory(articleId: articleId);
    final barcodes = group.barcodesOf(articleId);
    final heading = Theme.of(context).textTheme.titleMedium;

    return Scaffold(
      appBar: AppBar(
        title: Text(article.name),
        actions: [
          IconButton(
            tooltip: 'Umbenennen',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final name = await promptText(
                context,
                title: 'Artikel umbenennen',
                initial: article.name,
              );
              if (name != null) {
                session.apply(group.updateArticle(articleId, {'name': name}));
              }
            },
          ),
          IconButton(
            tooltip: 'Endgültig löschen',
            icon: const Icon(Icons.delete_forever_outlined),
            onPressed: () async {
              if (await confirm(
                context,
                title: '„${article.name}“ endgültig löschen?',
                message:
                    'Der Artikel verschwindet für alle in der Gruppe, '
                    'samt Barcodes, Listeneinträgen und Preishistorie.',
              )) {
                session.apply(group.deleteArticle(articleId));
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String?>(
            initialValue: article.categoryId,
            decoration: const InputDecoration(
              labelText: 'Kategorie',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(child: Text('–')),
              for (final c in group.categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => session.apply(
              group.updateArticle(articleId, {'categoryId': v}),
            ),
          ),
          const SizedBox(height: 12),
          UnitField(
            label: 'Standardeinheit',
            value: article.defaultUnit,
            onChanged: (v) => session.apply(
              group.updateArticle(articleId, {'defaultUnit': v}),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('Barcodes', style: heading)),
              IconButton(
                tooltip: 'Barcode eintragen',
                icon: const Icon(Icons.add),
                onPressed: () async {
                  final code = await promptText(
                    context,
                    title: 'Barcode eintragen',
                    label: 'EAN/GTIN',
                  );
                  if (code != null) {
                    session.apply(group.assignBarcode(code, articleId));
                  }
                },
              ),
            ],
          ),
          if (barcodes.isEmpty) const Text('Keine Barcodes.'),
          for (final code in barcodes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.qr_code),
              title: Text(code),
              trailing: IconButton(
                tooltip: 'Entfernen',
                icon: const Icon(Icons.close),
                onPressed: () => session.apply(group.removeBarcode(code)),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('Preishistorie', style: heading)),
              if (prices.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    if (await confirm(
                      context,
                      title: 'Preishistorie von „${article.name}“ löschen?',
                    )) {
                      session.apply(
                        group.deletePriceHistory(articleId: articleId),
                      );
                    }
                  },
                  child: const Text('Alle löschen'),
                ),
            ],
          ),
          if (prices.isEmpty)
            const Text(
              'Noch keine Preise. Preise, die auf der Liste eingetragen '
              'sind, landen beim Aufräumen hier.',
            ),
          for (final p in prices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                [
                  formatCents(p.cents),
                  if (p.quantity != null)
                    'für ${formatQuantity(p.quantity, p.unit)}',
                ].join(' '),
              ),
              subtitle: Text(
                [
                  formatDate(p.millis),
                  if (p.shopId != null) group.shop(p.shopId!)?.name ?? '?',
                ].join(' · '),
              ),
              trailing: IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.close),
                onPressed: () => session.apply(group.deletePrice(p.id)),
              ),
            ),
        ],
      ),
    );
  }
}
