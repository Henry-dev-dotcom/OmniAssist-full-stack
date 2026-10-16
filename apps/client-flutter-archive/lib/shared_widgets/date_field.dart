import 'package:flutter/material.dart';

/// A date shown as text with pick and clear buttons. [value] and results are local dates.
class DateField extends StatelessWidget {
  const DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.clearable = true,
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    final v = value;
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(child: Text(v == null ? 'None' : l.formatMediumDate(v))),
          IconButton(
            tooltip: 'Pick $label',
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: v ?? now,
                firstDate: DateTime(now.year - 10),
                lastDate: DateTime(now.year + 10),
                helpText: label,
              );
              if (picked != null) onChanged(picked);
            },
          ),
          if (clearable && v != null)
            IconButton(
              tooltip: 'Clear $label',
              icon: const Icon(Icons.clear),
              onPressed: () => onChanged(null),
            ),
        ],
      ),
    );
  }
}
