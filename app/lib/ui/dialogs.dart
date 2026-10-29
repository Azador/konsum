import 'package:flutter/material.dart';

/// Fragt einen Text ab; null bei Abbruch oder leerer Eingabe.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Name',
  String confirm = 'OK',
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(
      title: title,
      initial: initial,
      label: label,
      confirm: confirm,
    ),
  );
  final t = result?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// Hält den Controller selbst, damit er erst freigegeben wird, wenn der
/// Dialog ganz verschwunden ist (nicht schon während er ausgeblendet wird).
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.initial,
    required this.label,
    required this.confirm,
  });

  final String title;
  final String initial;
  final String label;
  final String confirm;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.confirm),
      ),
    ],
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String action = 'Löschen',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
