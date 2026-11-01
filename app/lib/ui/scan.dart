import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:konsum_core/konsum_core.dart';

import '../services/open_food_facts.dart';
import '../state/group_session.dart';
import 'camera_scanner.dart';
import 'dialogs.dart';
import 'format.dart';
import 'scope.dart';

/// Kamera-Scanner gibt es auf Android, iOS und im Browser. Unter Linux wird
/// der Barcode eingetippt oder mit einem USB-Handscanner (der sich wie eine
/// Tastatur verhält) in das Eingabefeld gescannt.
bool get cameraScanAvailable =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Liest einen Barcode ein: per Kamera, sonst per Eingabe.
Future<String?> scanBarcode(BuildContext context) async {
  if (!cameraScanAvailable) return _enterBarcode(context);
  final result = await Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => const _ScanPage()),
  );
  if (result == _manual && context.mounted) return _enterBarcode(context);
  return result == _manual ? null : result;
}

const _manual = '\u0000manual';

Future<String?> _enterBarcode(BuildContext context) => promptText(
  context,
  title: 'Barcode',
  label: 'Eintippen oder mit Handscanner scannen',
);

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Barcode scannen'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _manual),
          child: const Text('Eintippen'),
        ),
      ],
    ),
    body: CameraScanner(
      onCode: (code) {
        if (_done) return;
        _done = true;
        Navigator.pop(context, code);
      },
    ),
  );
}

/// Verarbeitet einen gescannten Barcode auf einer Liste:
/// bekannt und offen auf der Liste → abhaken; bekannt → hinzufügen;
/// unbekannt → Produkt nachschlagen und einem Artikel zuordnen.
Future<void> handleListScan(
  BuildContext context,
  GroupSession session,
  String listId,
  String code,
) async {
  final group = session.group;
  final status = AppScope.of(context).status;
  var article = group.articleForBarcode(code);

  if (article == null) {
    final info = await _lookup(code);
    if (!context.mounted) return;
    final articleId = await assignBarcodeDialog(context, session, code, info);
    if (articleId == null) return;
    article = group.article(articleId)!;
  } else if (group.productInfo(code) == null) {
    // Produktdaten nachtragen, ohne zu warten.
    _lookup(code).then((info) {
      if (info != null) session.apply(group.setProductInfo(code, info));
    });
  }

  final entry = group
      .entries(listId)
      .where((e) => e.articleId == article!.id)
      .firstOrNull;
  if (entry != null && !entry.checked) {
    session.apply(group.setChecked(listId, article.id, true));
    status.show(
      '${article.name} abgehakt',
      actionLabel: 'Rückgängig',
      onAction: () =>
          session.apply(group.setChecked(listId, article!.id, false)),
    );
  } else {
    session.apply(group.addToList(listId, article.id));
    status.show(
      '${article.name} hinzugefügt',
      actionLabel: 'Rückgängig',
      onAction: () => session.apply(group.removeFromList(listId, article!.id)),
    );
  }
}

Future<ProductInfo?> _lookup(String code) async {
  try {
    return await openFoodFacts.lookup(code);
  } catch (_) {
    return null; // offline oder Dienst nicht erreichbar
  }
}

/// Ordnet einen unbekannten Barcode einem vorhandenen oder neuen Artikel zu.
/// Liefert die Artikel-ID oder null bei Abbruch.
Future<String?> assignBarcodeDialog(
  BuildContext context,
  GroupSession session,
  String code,
  ProductInfo? info,
) async {
  final articleId = await showDialog<String>(
    context: context,
    builder: (_) => _AssignDialog(session: session, code: code, info: info),
  );
  if (articleId == null) return null;
  session.apply([
    ...session.group.assignBarcode(code, articleId),
    if (info != null) ...session.group.setProductInfo(code, info),
    ..._packSizeFrom(session, articleId, info),
  ]);
  return articleId;
}

/// Übernimmt die Packungsgröße aus den Produktdaten („500 g“), wenn der
/// Artikel noch keine hat.
List<Change> _packSizeFrom(
  GroupSession session,
  String articleId,
  ProductInfo? info,
) {
  final amount = parseAmount(info?.quantity ?? '');
  final article = session.group.article(articleId);
  if (amount == null || article == null || article.packSize != null) {
    return const [];
  }
  return session.group.updateArticle(articleId, {
    'packSize': amount.size,
    'packUnit': amount.unit,
  });
}

/// Ordnet einem Artikel einen Barcode zu (Scan oder Eingabe) und schlägt
/// das Produkt nach.
Future<void> addBarcodeToArticle(
  BuildContext context,
  GroupSession session,
  String articleId,
) async {
  final code = await scanBarcode(context);
  if (code == null) return;
  session.apply(session.group.assignBarcode(code, articleId));
  final info = await _lookup(code);
  if (info != null) {
    session.apply([
      ...session.group.setProductInfo(code, info),
      ..._packSizeFrom(session, articleId, info),
    ]);
  }
}

class _AssignDialog extends StatefulWidget {
  const _AssignDialog({
    required this.session,
    required this.code,
    required this.info,
  });

  final GroupSession session;
  final String code;
  final ProductInfo? info;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  late final _name = TextEditingController(text: widget.info?.name ?? '');

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.session.group;
    final info = widget.info;
    final words = _name.text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
    final matches = group.articles
        .where((a) {
          final n = a.name.toLowerCase();
          return words.isEmpty || words.any(n.contains);
        })
        .take(8)
        .toList();

    return AlertDialog(
      title: const Text('Unbekannter Barcode'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.code),
            if (info != null)
              Text(
                [?info.brand, ?info.name, ?info.quantity].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Text(
                'In Open Food Facts und den Schwester-Datenbanken nicht '
                'gefunden.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Artikel suchen oder neu benennen',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (matches.isNotEmpty) const Text('Zuordnen zu:'),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in matches)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.link),
                      title: Text(a.name),
                      onTap: () => Navigator.pop(context, a.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () {
                  final r = group.createArticle(_name.text.trim());
                  widget.session.apply(r.changes);
                  Navigator.pop(context, r.id);
                },
          child: const Text('Neu anlegen'),
        ),
      ],
    );
  }
}
