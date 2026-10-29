import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../state/group_session.dart';
import 'dialogs.dart';
import 'format.dart';
import 'price_dialog.dart';
import 'scan.dart';
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.scale_outlined),
            title: const Text('Packungsgröße'),
            subtitle: Text(
              article.packSize == null
                  ? 'Keine (z. B. 500 g, 1,5 l)'
                  : formatQuantity(article.packSize, article.packUnit),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final text = await promptText(
                context,
                title: 'Packungsgröße',
                label: 'z. B. 500 g oder 1,5 l (leer: keine)',
                initial: article.packSize == null
                    ? ''
                    : formatQuantity(article.packSize, article.packUnit),
              );
              if (text == null) return;
              final amount = parseAmount(text);
              session.apply(
                group.updateArticle(articleId, {
                  'packSize': amount?.size,
                  'packUnit': amount?.unit,
                }),
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('Barcodes', style: heading)),
              IconButton(
                tooltip: 'Barcode hinzufügen',
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () =>
                    addBarcodeToArticle(context, session, articleId),
              ),
            ],
          ),
          if (barcodes.isEmpty) const Text('Keine Barcodes.'),
          for (final code in barcodes)
            _BarcodeTile(session: session, code: code),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('Preishistorie', style: heading)),
              IconButton(
                tooltip: 'Preis eintragen',
                icon: const Icon(Icons.add),
                onPressed: () => showPriceDialog(
                  context,
                  session,
                  articleId,
                  shopId: AppScope.of(context).shopFor(session),
                ),
              ),
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
                  if (formatAmount(
                        quantity: p.quantity,
                        unit: p.unit,
                        packSize: p.packSize,
                        packUnit: p.packUnit,
                      )
                      case final amount?)
                    'für $amount',
                  if (p.basePriceCents case final b?)
                    '(${formatBasePrice(b, p.base!.unit)})',
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

const _nutrimentLabels = {
  'energy-kcal': ('Energie', 'kcal'),
  'fat': ('Fett', 'g'),
  'saturated-fat': ('davon gesättigte Fettsäuren', 'g'),
  'carbohydrates': ('Kohlenhydrate', 'g'),
  'sugars': ('davon Zucker', 'g'),
  'proteins': ('Eiweiß', 'g'),
  'salt': ('Salz', 'g'),
};

/// Ein Barcode mit Produktdaten und Nährwerten (aufklappbar).
class _BarcodeTile extends StatelessWidget {
  const _BarcodeTile({required this.session, required this.code});

  final GroupSession session;
  final String code;

  @override
  Widget build(BuildContext context) {
    final info = session.group.productInfo(code);
    final remove = IconButton(
      tooltip: 'Barcode entfernen',
      icon: const Icon(Icons.close),
      onPressed: () => session.apply(session.group.removeBarcode(code)),
    );
    if (info == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.qr_code),
        title: Text(code),
        trailing: remove,
      );
    }
    final number = NumberFormat.decimalPattern('de');
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.qr_code),
      title: Text([?info.brand, ?info.name].join(' · ')),
      subtitle: Text([code, ?info.quantity].join(' · ')),
      trailing: remove,
      childrenPadding: const EdgeInsets.only(left: 40, bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (info.nutriments.isEmpty)
          const Text('Keine Nährwerte bekannt.')
        else ...[
          const Text('Nährwerte je 100 g/ml'),
          for (final e in _nutrimentLabels.entries)
            if (info.nutriments[e.key] case final num v)
              Text('${e.value.$1}: ${number.format(v)} ${e.value.$2}'),
        ],
        if (info.nutriScore != null)
          Text('Nutri-Score: ${info.nutriScore!.toUpperCase()}'),
        const SizedBox(height: 4),
        Text(
          'Daten: Open Food Facts (ODbL)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
