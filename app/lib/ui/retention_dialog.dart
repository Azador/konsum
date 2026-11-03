import 'package:flutter/material.dart';
import 'package:konsum_core/konsum_core.dart';

/// „6 Monate (Vorgabe)“, „1 Monat“, „ohne automatisches Löschen“.
String retentionLabel(int months) => switch (months) {
  <= 0 => 'Ohne automatisches Löschen',
  1 => '1 Monat',
  Group.defaultRetentionMonths => '$months Monate (Vorgabe)',
  _ => '$months Monate',
};

/// Lässt die Aufbewahrungsfrist wählen: 1–24 Monate oder 0 für „ohne
/// automatisches Löschen“. null bei Abbruch.
Future<int?> pickRetention(BuildContext context, int current) =>
    showDialog<int>(
      context: context,
      builder: (_) => _RetentionDialog(current),
    );

class _RetentionDialog extends StatefulWidget {
  const _RetentionDialog(this.current);

  final int current;

  @override
  State<_RetentionDialog> createState() => _RetentionDialogState();
}

class _RetentionDialogState extends State<_RetentionDialog> {
  late bool _never = widget.current <= 0;
  late double _months = widget.current <= 0
      ? Group.defaultRetentionMonths.toDouble()
      : widget.current.clamp(1, 24).toDouble();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Aufbewahrung'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Wie lange Käufe (für die Vorschläge) und Spuren gelöschter '
          'Einträge aufbewahrt werden. Die Einstellung gilt für alle '
          'Mitglieder der Gruppe.',
        ),
        const SizedBox(height: 16),
        Text(
          _never ? retentionLabel(0) : retentionLabel(_months.round()),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Slider(
          value: _months,
          min: 1,
          max: 24,
          divisions: 23,
          label: retentionLabel(_months.round()),
          onChanged: _never ? null : (v) => setState(() => _months = v),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Nicht automatisch löschen'),
          value: _never,
          onChanged: (v) => setState(() => _never = v ?? false),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _never ? 0 : _months.round()),
        child: const Text('Übernehmen'),
      ),
    ],
  );
}
