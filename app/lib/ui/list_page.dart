import 'package:flutter/material.dart';
import 'package:konsum_core/konsum_core.dart';

import '../services/open_food_facts.dart';
import '../state/group_session.dart';
import 'dialogs.dart';
import 'drawer.dart';
import 'entry_sheet.dart';
import 'format.dart';
import 'scan.dart';
import 'scope.dart';
import 'status_line.dart';

/// Hauptseite: die gewählte Liste mit Eingabezeile zum Hinzufügen.
class ListPage extends StatefulWidget {
  const ListPage({super.key, required this.session, required this.listId});

  final GroupSession session;
  final String listId;

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  /// Schlüssel der Einträge, um zu einem neuen hinzuscrollen.
  final _entryKeys = <String, GlobalKey>{};

  /// Ob die Bildschirmtastatur beim letzten Aufbau offen war.
  bool _keyboardOpen = false;

  GroupSession get _session => widget.session;
  Group get _group => widget.session.group;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String input) {
    // Ein Handscanner tippt den Barcode ins Feld und schickt Enter.
    if (OpenFoodFacts.isProductCode(input.trim())) {
      _input.clear();
      _scan(input.trim());
      return;
    }
    final parsed = parseQuickAdd(input);
    if (parsed.name.isEmpty) return;
    final existing = _group.articles
        .where((a) => a.name.toLowerCase() == parsed.name.toLowerCase())
        .firstOrNull;
    _addArticle(
      existing?.id,
      name: parsed.name,
      quantity: parsed.quantity,
      unit: parsed.unit,
    );
  }

  void _addArticle(
    String? articleId, {
    String? name,
    num? quantity,
    String? unit,
  }) {
    final changes = <Change>[];
    if (articleId == null) {
      final r = _group.createArticle(name!, defaultUnit: unit);
      articleId = r.id;
      changes.addAll(r.changes);
    }
    changes.addAll(
      _group.addToList(
        widget.listId,
        articleId,
        quantity: quantity,
        unit: unit,
      ),
    );
    _session.apply(changes);
    _input.clear();
    _focus.requestFocus();
    _scrollTo(articleId);
  }

  Future<void> _scan(String code) async {
    final added = await handleListScan(context, _session, widget.listId, code);
    if (added != null) _scrollTo(added);
  }

  /// Scrollt nach dem nächsten Aufbau so, dass der Eintrag zu sehen ist.
  void _scrollTo(String articleId) {
    final id = ListEntry.entryId(widget.listId, articleId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _entryKeys[id]?.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        // Mittig, damit er nicht unter den Vorschlägen liegt.
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Schließt man die Tastatur (z. B. mit „Zurück“), behält das Feld auf
  /// Android den Fokus. Dann auch den Fokus und damit die Vorschläge weg.
  void _watchKeyboard(BuildContext context) {
    final open = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (_keyboardOpen && !open && _focus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.unfocus());
    }
    _keyboardOpen = open;
  }

  @override
  Widget build(BuildContext context) {
    _watchKeyboard(context);
    final app = AppScope.of(context);
    final list = _group.lists.where((l) => l.id == widget.listId).firstOrNull;
    final shopId = app.shopFor(_session);
    final all = _group.entries(widget.listId, shopId: shopId);
    final open = all.where((e) => !e.checked).toList();
    final checked = all.where((e) => e.checked).toList();
    final total = _group.listTotal(widget.listId, shopId: shopId);

    return Scaffold(
      drawer: const GroupDrawer(),
      appBar: AppBar(
        title: Text(list?.name ?? ''),
        actions: [
          _ShopMenu(session: _session, shopId: shopId),
          IconButton(
            tooltip: app.showChecked
                ? 'Abgehakte ausblenden'
                : 'Abgehakte einblenden',
            icon: Icon(
              app.showChecked ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: app.toggleShowChecked,
          ),
          IconButton(
            tooltip: 'Abgehakte entfernen',
            icon: Badge(
              isLabelVisible: checked.isNotEmpty,
              label: Text('${checked.length}'),
              child: const Icon(Icons.cleaning_services_outlined),
            ),
            onPressed: checked.isEmpty
                ? null
                : () => _session.apply(
                    _group.clearChecked(widget.listId, shopId: shopId),
                  ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'rename') {
                final name = await promptText(
                  context,
                  title: 'Liste umbenennen',
                  initial: list?.name ?? '',
                );
                if (name != null) {
                  _session.apply(_group.renameList(widget.listId, name));
                }
              } else if (v == 'delete' &&
                  await confirm(
                    context,
                    title: 'Liste löschen?',
                    message:
                        'Die Liste wird für alle in der Gruppe gelöscht. '
                        'Artikel und Preise bleiben erhalten.',
                  )) {
                app.deleteList(_session, widget.listId);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
              PopupMenuItem(value: 'delete', child: Text('Liste löschen')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _listAndTotal(all, open, checked, total, shopId),
                ),
                if (_focus.hasFocus)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _suggestions(),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _input,
              focusNode: _focus,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Hinzufügen, z. B. „2 kg Mehl“',
                prefixIcon: const Icon(Icons.add_shopping_cart),
                border: const OutlineInputBorder(),
                suffixIcon: _input.text.isEmpty
                    ? IconButton(
                        tooltip: 'Barcode scannen',
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: () async {
                          final code = await scanBarcode(context);
                          if (code != null && context.mounted) {
                            await _scan(code);
                          }
                        },
                      )
                    : IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () => _add(_input.text),
                      ),
              ),
              onSubmitted: _add,
            ),
          ),
          const StatusLine(),
        ],
      ),
    );
  }

  /// Liste der Einträge, darunter die Summe.
  Widget _listAndTotal(
    List<ListEntry> all,
    List<ListEntry> open,
    List<ListEntry> checked,
    ({int cents, int unknown}) total,
    String? shopId,
  ) {
    final app = AppScope.of(context);
    final ids = {for (final e in all) e.id};
    _entryKeys.removeWhere((id, _) => !ids.contains(id));
    return Column(
      children: [
        Expanded(
          child: all.isEmpty
              ? const Center(child: Text('Die Liste ist leer.'))
              // Alle Einträge gebaut (keine lange Liste), damit sich jeder
              // per ensureVisible in die Sicht holen lässt.
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ..._withHeaders(open, shopId != null),
                      if (checked.isNotEmpty && app.showChecked) ...[
                        const Divider(),
                        for (final e in checked) _tile(e, shopId),
                      ],
                      if (checked.isNotEmpty && !app.showChecked)
                        ListTile(
                          dense: true,
                          title: Text('${checked.length} abgehakt'),
                          onTap: app.toggleShowChecked,
                        ),
                    ],
                  ),
                ),
        ),
        if (total.cents > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  'Summe ca. ${formatCents(total.cents)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (total.unknown > 0) Text('  (${total.unknown} ohne Preis)'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _tile(ListEntry e, String? shopId) => KeyedSubtree(
    key: _entryKeys.putIfAbsent(e.id, GlobalKey.new),
    child: _EntryTile(_session, e, shopId),
  );

  /// Vorschläge, halbdurchsichtig über dem unteren Rand der Liste; nur so
  /// hoch wie nötig, höchstens drei Zeilen.
  Widget _suggestions() {
    final query = parseQuickAdd(_input.text);
    final items = _group
        .suggestions(widget.listId, query: query.name)
        .take(12)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surface.withValues(alpha: 0.25),
      constraints: const BoxConstraints(maxHeight: 132),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 6,
          runSpacing: 0,
          children: [
            for (final a in items)
              ActionChip(
                label: Text(a.name),
                // Deckend, damit der Name über der Liste lesbar bleibt.
                backgroundColor: colors.secondaryContainer,
                side: BorderSide.none,
                elevation: 2,
                onPressed: () => _addArticle(
                  a.id,
                  quantity: query.quantity,
                  unit: query.unit,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Einträge, bei gewähltem Laden mit Kategorie-Überschriften.
  List<Widget> _withHeaders(List<ListEntry> entries, bool headers) {
    final result = <Widget>[];
    String? lastCategory = '';
    final names = {for (final c in _group.categories) c.id: c.name};
    for (final e in entries) {
      if (headers) {
        final catId = _group.article(e.articleId)?.categoryId;
        final category = names[catId];
        if (category != lastCategory) {
          result.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                category ?? 'Sonstiges',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          );
          lastCategory = category;
        }
      }
      result.add(_tile(e, AppScope.of(context).shopFor(_session)));
    }
    return result;
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.session, this.entry, this.shopId);

  final GroupSession session;
  final ListEntry entry;
  final String? shopId;

  @override
  Widget build(BuildContext context) {
    final group = session.group;
    final article = group.article(entry.articleId)!;
    final privateNote = session.private.note(entry.id);
    final price = group.estimatedPrice(entry, shopId: shopId);
    final estimated = entry.totalCents == null;
    final base = entry.base;
    final basePrice = estimated
        ? group.lastPrice(entry.articleId, shopId: shopId)?.basePriceCents
        : entry.basePriceCents;
    final details = [
      ?formatAmount(
        quantity: entry.quantity,
        unit: entry.unit,
        packSize: entry.packSize,
        packUnit: entry.packUnit,
      ),
      ?entry.note,
      if (privateNote != null) '🔒 $privateNote',
    ].where((s) => s.isNotEmpty).join(' · ');
    final muted = entry.checked
        ? TextStyle(
            decoration: TextDecoration.lineThrough,
            color: Theme.of(context).disabledColor,
          )
        : null;

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.remove_shopping_cart),
      ),
      onDismissed: (_) =>
          session.apply(group.removeFromList(entry.listId, entry.articleId)),
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        value: entry.checked,
        onChanged: (v) => session.apply(
          group.setChecked(entry.listId, entry.articleId, v ?? false),
        ),
        title: Text(article.name, style: muted),
        subtitle: details.isEmpty ? null : Text(details, style: muted),
        secondary: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (price != null)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    estimated ? '≈ ${formatCents(price)}' : formatCents(price),
                    style: muted,
                  ),
                  if (basePrice != null && base != null)
                    Text(
                      formatBasePrice(basePrice, base.unit),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.merge(muted),
                    ),
                ],
              ),
            IconButton(
              tooltip: 'Bearbeiten',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showEntrySheet(context, session, entry),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopMenu extends StatelessWidget {
  const _ShopMenu({required this.session, required this.shopId});

  final GroupSession session;
  final String? shopId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final shops = session.group.shops;
    final current = shopId == null ? null : session.group.shop(shopId!);
    return PopupMenuButton<String>(
      tooltip: 'Laden wählen',
      onSelected: (id) => app.selectShop(session, id.isEmpty ? null : id),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: '',
          child: Text('Kein Laden (alphabetisch)'),
        ),
        for (final s in shops) PopupMenuItem(value: s.id, child: Text(s.name)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Icon(Icons.storefront_outlined),
            if (current != null) ...[
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(current.name, overflow: TextOverflow.ellipsis),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
