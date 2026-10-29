import 'package:flutter/material.dart';
import 'package:konsum_core/konsum_core.dart';

import 'format.dart';

/// Auswahl einer Mengeneinheit (oder keiner).
class UnitField extends StatelessWidget {
  const UnitField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Einheit',
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      const DropdownMenuItem(child: Text('–')),
      for (final u in Units.all)
        DropdownMenuItem(value: u, child: Text(unitLabel(u))),
    ],
    onChanged: onChanged,
  );
}
