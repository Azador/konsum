import 'package:flutter/material.dart';
import 'package:konsum_core/konsum_core.dart';

import '../state/group_session.dart';
import 'article_page.dart';
import 'dialogs.dart';
import 'format.dart';
import 'purchase_dialog.dart';
import 'retention_dialog.dart';
import 'scope.dart';

/// Kaufhistorie der Gruppe, neueste zuerst, nach Tagen gegliedert.
class PurchasesPage extends StatelessWidget {
  const PurchasesPage({super.key, required this.session});

  final GroupSession session;

  @override
  Widget build(BuildContext context) {
    AppScope.of(context);
    final group = session.group;
    final purchases = group.purchasesOf();
    final months = group.retentionMonths;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          'Käufe entstehen beim Aufräumen der Liste. Sie sortieren die '
          'Vorschläge und ergeben den Verbrauch für wiederkehrende Artikel. '
          '${months <= 0 ? 'Sie werden nicht automatisch gelöscht.' : 'Aufbewahrung: ${retentionLabel(months)}.'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      if (purchases.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Noch keine Käufe.'),
        ),
    ];
    String? lastDay;
    for (final p in purchases) {
      final day = formatDate(p.millis);
      if (day != lastDay) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              day,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        );
        lastDay = day;
      }
      children.add(
        PurchaseTile(session: session, purchase: p, showArticle: true),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Käufe'),
        actions: [
          if (purchases.isNotEmpty)
            TextButton(
              onPressed: () async {
                if (await confirm(
                  context,
                  title: 'Gesamte Kaufhistorie löschen?',
                  message:
                      'Alle Käufe der Gruppe werden für alle Mitglieder '
                      'gelöscht. Vorschläge und wiederkehrende Artikel '
                      'fangen dann von vorn an.',
                )) {
                  session.apply(group.deletePurchases());
                }
              },
              child: const Text('Alle löschen'),
            ),
        ],
      ),
      body: ListView(children: children),
    );
  }
}

/// Ein Kauf: Menge, Laden, Liste; mit [showArticle] auch der Artikel (zum
/// Antippen), sonst das Datum.
class PurchaseTile extends StatelessWidget {
  const PurchaseTile({
    super.key,
    required this.session,
    required this.purchase,
    this.showArticle = false,
  });

  final GroupSession session;
  final Purchase purchase;
  final bool showArticle;

  @override
  Widget build(BuildContext context) {
    final group = session.group;
    final p = purchase;
    final amount = switch (p.amount) {
      null => 'Menge unbekannt',
      final a => formatAmountOf(a) ?? '1 ${unitLabel(a.unit ?? Units.pack)}',
    };
    final where = [
      if (p.shopId != null) group.shop(p.shopId!)?.name ?? '?',
      if (group.lists.where((l) => l.id == p.listId).firstOrNull
          case final list?)
        list.name,
    ];
    final details = [
      if (showArticle) amount else formatDate(p.millis),
      ...where,
    ].join(' · ');
    return ListTile(
      contentPadding: showArticle
          ? const EdgeInsets.only(left: 16, right: 4)
          : EdgeInsets.zero,
      title: Text(
        showArticle ? group.article(p.articleId)?.name ?? '?' : amount,
      ),
      subtitle: Text(details),
      onTap: showArticle
          ? () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    ArticlePage(session: session, articleId: p.articleId),
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Menge korrigieren',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final amount = await showPurchaseAmountDialog(context, p.amount);
              if (amount != null) {
                session.apply(group.updatePurchase(p.id, amount));
              }
            },
          ),
          IconButton(
            tooltip: 'Kauf löschen',
            icon: const Icon(Icons.close),
            onPressed: () => session.apply(group.deletePurchase(p.id)),
          ),
        ],
      ),
    );
  }
}
