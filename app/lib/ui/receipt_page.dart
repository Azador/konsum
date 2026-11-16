import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:konsum_core/konsum_core.dart';

import '../services/receipt_image.dart' show ocrVariants;
import '../services/receipt_ocr.dart';
import '../state/group_session.dart';
import 'dialogs.dart';
import 'format.dart';
import 'scope.dart';

/// Kassenbon fotografieren, Positionen prüfen, Preise übernehmen.
///
/// Noch im Test: erreichbar über das Seitenmenü.
class ReceiptPage extends StatefulWidget {
  const ReceiptPage({
    super.key,
    required this.session,
    this.engine,
    this.photo,
  });

  final GroupSession session;

  /// Für Tests ersetzbar.
  final OcrEngine? engine;

  /// Gleich dieses Foto lesen (für Tests).
  final Uint8List? photo;

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _Row {
  _Row(this.line, this.match)
    : articleId = match.articleId,
      ignore = match.ignore,
      take = match.confident;

  final ReceiptLine line;
  ReceiptMatch match;
  String? articleId;
  bool ignore;
  bool take;

  /// Von Hand geändert: bei Ladenwechsel nicht neu vorschlagen.
  bool touched = false;
}

class _ReceiptPageState extends State<ReceiptPage> {
  Uint8List? _photo;
  int _turns = 0;
  ({int done, int total})? _progress;
  String? _error;
  Receipt? _receipt;
  List<_Row> _rows = [];
  String? _shopId;
  String? _listId;

  Group get _group => widget.session.group;

  @override
  void initState() {
    super.initState();
    if (widget.photo != null) {
      _photo = widget.photo;
      WidgetsBinding.instance.addPostFrameCallback((_) => _read(null));
    }
  }

  bool get _camera => !kIsWeb && Platform.isAndroid;

  Future<void> _pick(ImageSource source) async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source);
    } catch (e) {
      setState(() => _error = 'Foto nicht verfügbar: $e');
      return;
    }
    if (file == null) return;
    _photo = await file.readAsBytes();
    await _read(null);
  }

  Future<void> _read(int? turns) async {
    final photo = _photo;
    if (photo == null) return;
    setState(() {
      _error = null;
      _receipt = null;
      _progress = (done: 0, total: ocrVariants.length);
    });
    try {
      final r = await readReceiptPhoto(
        photo,
        engine: widget.engine,
        quarterTurns: turns,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = (done: done, total: total));
        },
      );
      if (!mounted) return;
      final app = AppScope.of(context);
      _listId = app.currentGroup == widget.session ? app.currentListId : null;
      _shopId =
          shopFromReceipt(_group, r.receipt.header)?.id ??
          app.shopFor(widget.session) ??
          _recentShop();
      setState(() {
        _turns = r.quarterTurns;
        _receipt = r.receipt;
        _progress = null;
        _rows = [
          for (final l in r.receipt.lines) _Row(l, const ReceiptMatch()),
        ];
        _rematch();
      });
    } on OcrException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Fehler beim Lesen: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _progress = null;
    });
  }

  String? _recentShop() {
    final since = DateTime.now()
        .subtract(ReceiptGroup.tripWindow)
        .millisecondsSinceEpoch;
    for (final p in _group.purchases) {
      if (p.millis >= since && p.shopId != null) return p.shopId;
    }
    return null;
  }

  ReceiptMatcher get _matcher => ReceiptMatcher(
    _group,
    shopId: _shopId,
    trip: _group.receiptTrip(listId: _listId),
  );

  /// Vorschläge neu berechnen (z. B. nach Ladenwechsel), außer für von Hand
  /// geänderte Zeilen.
  void _rematch() {
    final m = _matcher;
    for (final r in _rows) {
      r.match = m.match(r.line);
      if (r.touched) continue;
      r.articleId = r.match.articleId;
      r.ignore = r.match.ignore;
      r.take = r.match.confident;
    }
  }

  void _apply() {
    final lines = [
      for (final r in _rows)
        if (r.take && r.line.cents != null && (r.ignore || r.articleId != null))
          ReceiptAssignment.of(
            r.line,
            articleId: r.ignore ? null : r.articleId,
            ignore: r.ignore,
          ),
    ];
    final changes = _group.applyReceipt(
      lines,
      shopId: _shopId,
      listId: _listId,
    );
    widget.session.apply(changes);
    final prices = lines.where((l) => !l.ignore).length;
    AppScope.of(context).status
        .show(prices == 1 ? '1 Preis übernommen' : '$prices Preise übernommen');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    final taken = _rows.where(
      (r) => r.take && !r.ignore && r.articleId != null,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kassenbon (Test)'),
        actions: [
          if (_photo != null && _progress == null)
            IconButton(
              tooltip: 'Foto drehen',
              icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
              onPressed: () => _read((_turns + 1) % 4),
            ),
          if (_progress == null) ..._sourceButtons(),
        ],
      ),
      body: _progress != null
          ? _Progress(_progress!)
          : receipt == null
          ? _Start(error: _error, camera: _camera, onPick: _pick)
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [_header(receipt), for (final r in _rows) _rowTile(r)],
            ),
      floatingActionButton: receipt == null
          ? null
          : FloatingActionButton.extended(
              onPressed: taken.isEmpty && !_rows.any((r) => r.take && r.ignore)
                  ? null
                  : _apply,
              icon: const Icon(Icons.check),
              label: Text('${taken.length} übernehmen'),
            ),
    );
  }

  List<Widget> _sourceButtons() => [
    if (_camera)
      IconButton(
        tooltip: 'Foto aufnehmen',
        icon: const Icon(Icons.photo_camera_outlined),
        onPressed: () => _pick(ImageSource.camera),
      ),
    IconButton(
      tooltip: 'Foto auswählen',
      icon: const Icon(Icons.photo_library_outlined),
      onPressed: () => _pick(ImageSource.gallery),
    ),
  ];

  Widget _header(Receipt receipt) {
    final theme = Theme.of(context);
    final total = receipt.totalCents;
    final sum = receipt.sumCents;
    final (icon, color, text) = total == null
        ? (
            Icons.help_outline,
            theme.colorScheme.onSurfaceVariant,
            'Summe ${formatCents(sum)} · Bonsumme nicht lesbar',
          )
        : receipt.balanced
        ? (
            Icons.check_circle_outline,
            theme.colorScheme.primary,
            'Summe ${formatCents(sum)} · stimmt mit dem Bon überein',
          )
        : (
            Icons.error_outline,
            theme.colorScheme.error,
            'Positionen ${formatCents(sum)} · Bon ${formatCents(total)}',
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String?>(
            initialValue: _shopId,
            decoration: const InputDecoration(labelText: 'Laden'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Kein Laden')),
              for (final s in _group.shops)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (id) => setState(() {
              _shopId = id;
              _rematch();
            }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: TextStyle(color: color)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowTile(_Row r) {
    final theme = Theme.of(context);
    final line = r.line;
    final article = r.articleId == null ? null : _group.article(r.articleId!);
    final muted = theme.colorScheme.onSurfaceVariant;
    final String target;
    TextStyle? targetStyle;
    if (r.ignore) {
      target = 'wird ignoriert';
      targetStyle = TextStyle(color: muted, fontStyle: FontStyle.italic);
    } else if (article == null) {
      target = 'Artikel wählen …';
      targetStyle = TextStyle(color: muted);
    } else {
      target = r.match.confident || r.touched
          ? article.name
          : '${article.name}?';
      targetStyle = TextStyle(
        color: r.match.confident || r.touched ? null : muted,
        fontWeight: FontWeight.w500,
      );
    }
    final qty = line.quantity != null && line.unitCents != null
        ? '${formatQuantity(line.quantity, null)} × '
              '${formatCents(line.unitCents!)}'
        : null;
    return ListTile(
      leading: Checkbox(
        value: r.take,
        onChanged: (v) => setState(() {
          r.take = v ?? false;
          r.touched = true;
        }),
      ),
      title: Text(
        line.text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      ),
      subtitle: Text('→ $target', style: targetStyle),
      trailing: InkWell(
        onTap: () => _editPrice(r),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              line.cents == null ? '?' : formatCents(line.cents!),
              style: line.check == ReceiptCheck.none && line.votes < 4
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
            if (qty != null) Text(qty, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      onTap: () => _choose(r),
    );
  }

  Future<void> _editPrice(_Row r) async {
    final text = await promptText(
      context,
      title: 'Preis',
      label: r.line.text,
      initial: r.line.cents == null ? '' : formatCentsInput(r.line.cents!),
    );
    if (text == null) return;
    final cents = parseCents(text);
    if (cents != null) setState(() => r.line.cents = cents);
  }

  Future<void> _choose(_Row r) async {
    final result = await showDialog<_Choice>(
      context: context,
      builder: (_) => _ArticleChooser(
        group: _group,
        line: r.line,
        matcher: _matcher,
        current: r.articleId,
      ),
    );
    if (result == null || !mounted) return;
    var articleId = result.articleId;
    if (result.create != null) {
      final created = _group.createArticle(result.create!);
      widget.session.apply(created.changes);
      articleId = created.id;
    }
    setState(() {
      r.touched = true;
      r.ignore = result.ignore;
      r.articleId = result.ignore ? null : articleId;
      r.take = result.ignore || articleId != null;
    });
  }
}

class _Start extends StatelessWidget {
  const _Start({
    required this.error,
    required this.camera,
    required this.onPick,
  });

  final String? error;
  final bool camera;
  final void Function(ImageSource) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Den ganzen Bon flach hinlegen und von oben fotografieren. '
              'Die Positionen werden auf dem Gerät gelesen; das Foto wird '
              'nicht gespeichert und nicht verschickt.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (camera)
              FilledButton.icon(
                onPressed: () => onPick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Foto aufnehmen'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => onPick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Foto auswählen'),
            ),
            if (error != null) ...[
              const SizedBox(height: 24),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.progress);

  final ({int done, int total}) progress;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              value: progress.total == 0
                  ? null
                  : progress.done / progress.total,
            ),
          ),
          const SizedBox(height: 16),
          Text('Bon wird gelesen … ${progress.done}/${progress.total}'),
        ],
      ),
    ),
  );
}

class _Choice {
  const _Choice({this.articleId, this.ignore = false, this.create});

  final String? articleId;
  final bool ignore;

  /// Name eines neuen Artikels.
  final String? create;
}

/// Artikel für eine Bonzeile wählen; passende zuerst.
class _ArticleChooser extends StatefulWidget {
  const _ArticleChooser({
    required this.group,
    required this.line,
    required this.matcher,
    required this.current,
  });

  final Group group;
  final ReceiptLine line;
  final ReceiptMatcher matcher;
  final String? current;

  @override
  State<_ArticleChooser> createState() => _ArticleChooserState();
}

class _ArticleChooserState extends State<_ArticleChooser> {
  final _query = TextEditingController();

  late final List<(Article, double)> _ranked = () {
    final m = widget.matcher;
    final list = [
      for (final a in widget.group.articles)
        (a, m.score(widget.line, a.id, [a.name])),
    ];
    list.sort((x, y) {
      final c = y.$2.compareTo(x.$2);
      return c != 0
          ? c
          : x.$1.name.toLowerCase().compareTo(y.$1.name.toLowerCase());
    });
    return list;
  }();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final shown = [
      for (final (a, _) in _ranked)
        if (q.isEmpty || a.name.toLowerCase().contains(q)) a,
    ];
    return AlertDialog(
      title: Text(
        widget.line.text,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _query,
                autofocus: !kIsWeb && !Platform.isAndroid,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Artikel suchen',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (q.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text('Neuer Artikel „${_query.text.trim()}“'),
                      onTap: () => Navigator.pop(
                        context,
                        _Choice(create: _query.text.trim()),
                      ),
                    ),
                  for (final a in shown)
                    ListTile(
                      title: Text(a.name),
                      selected: a.id == widget.current,
                      onTap: () =>
                          Navigator.pop(context, _Choice(articleId: a.id)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const _Choice(ignore: true)),
          child: const Text('Immer ignorieren'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, const _Choice()),
          child: const Text('Keinem zuordnen'),
        ),
      ],
    );
  }
}
