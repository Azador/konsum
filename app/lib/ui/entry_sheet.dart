import 'package:flutter/material.dart';
import 'package:konsum_core/konsum_core.dart';

import '../state/group_session.dart';
import 'article_page.dart';
import 'format.dart';
import 'unit_field.dart';

/// Bearbeiten eines Listeneintrags: Menge, Einheit, Preis, Notizen.
Future<void> showEntrySheet(
  BuildContext context,
  GroupSession session,
  ListEntry entry,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _EntrySheet(session: session, entry: entry),
);

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({required this.session, required this.entry});

  final GroupSession session;
  final ListEntry entry;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late final _quantity = TextEditingController(
    text: widget.entry.quantity == null
        ? ''
        : formatQuantity(widget.entry.quantity, null),
  );
  late final _price = TextEditingController(
    text: widget.entry.price == null
        ? ''
        : (widget.entry.price! / 100).toStringAsFixed(2).replaceAll('.', ','),
  );
  late final _note = TextEditingController(text: widget.entry.note ?? '');
  late final _privateNote = TextEditingController(
    text: widget.session.private.note(widget.entry.id) ?? '',
  );
  late String? _unit = widget.entry.unit;

  @override
  void dispose() {
    for (final c in [_quantity, _price, _note, _privateNote]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final e = widget.entry;
    final group = widget.session.group;
    final note = _note.text.trim();
    final fields = <String, Object?>{
      'quantity': parseNumber(_quantity.text),
      'unit': _unit,
      'note': note.isEmpty ? null : note,
      'price': parseCents(_price.text),
    };
    fields.removeWhere(
      (k, v) => switch (k) {
        'quantity' => v == e.quantity,
        'unit' => v == e.unit,
        'note' => v == e.note,
        _ => v == e.price,
      },
    );
    if (fields.isNotEmpty) {
      widget.session.apply(group.updateEntry(e.listId, e.articleId, fields));
    }
    final privateNote = _privateNote.text.trim();
    if (privateNote != (widget.session.private.note(e.id) ?? '')) {
      widget.session.applyPrivate(
        widget.session.private.setNote(e.id, privateNote),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.session.group;
    final article = group.article(widget.entry.articleId)!;
    final last = group.lastPrice(article.id);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    article.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Artikel'),
                  onPressed: () {
                    Navigator.of(context)
                      ..pop()
                      ..push(
                        MaterialPageRoute<void>(
                          builder: (_) => ArticlePage(
                            session: widget.session,
                            articleId: article.id,
                          ),
                        ),
                      );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Menge',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: UnitField(
                    value: _unit,
                    onChanged: (u) => setState(() => _unit = u),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Preis (€) für diese Menge',
                helperText: last == null
                    ? null
                    : 'Zuletzt: ${formatCents(last.cents)}'
                          '${last.quantity == null ? '' : ' für ${formatQuantity(last.quantity, last.unit)}'}'
                          ' am ${formatDate(last.millis)}'
                          '${last.shopId == null ? '' : ' bei ${group.shop(last.shopId!)?.name ?? '?'}'}',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Notiz für alle',
                prefixIcon: Icon(Icons.group_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _privateNote,
              decoration: const InputDecoration(
                labelText: 'Private Notiz (nur für mich)',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.remove_shopping_cart_outlined),
                  label: const Text('Von Liste nehmen'),
                  onPressed: () {
                    widget.session.apply(
                      group.removeFromList(
                        widget.entry.listId,
                        widget.entry.articleId,
                      ),
                    );
                    Navigator.pop(context);
                  },
                ),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Speichern')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
