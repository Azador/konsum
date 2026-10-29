import 'package:flutter/material.dart';

/// Fragt einen Text ab; null bei Abbruch oder leerer Eingabe.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Name',
  String confirm = 'OK',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(confirm),
        ),
      ],
    ),
  );
  controller.dispose();
  final t = result?.trim();
  return t == null || t.isEmpty ? null : t;
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
