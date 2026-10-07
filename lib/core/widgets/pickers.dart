import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../db/enums.dart';
import '../i18n/i18n.dart';

/// Bottom sheet list picker. Returns the chosen value or null.
Future<T?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) label,
  String Function(T)? subtitle,
  T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    ListTile(
                      title: Text(label(option)),
                      subtitle:
                          subtitle == null ? null : Text(subtitle(option)),
                      trailing: option == selected
                          ? const Icon(Icons.check, color: AppColors.successText)
                          : null,
                      onTap: () => Navigator.of(context).pop(option),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Read-only field that opens a picker when tapped (replaces dropdowns).
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radius),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        isEmpty: value == null,
        child: Text(value ?? '', style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

String paymentModeLabel(PaymentMode mode) => switch (mode) {
      PaymentMode.cash => tr('Cash'),
      PaymentMode.phonePe => tr('PhonePe'),
      PaymentMode.paytm => tr('Paytm'),
      PaymentMode.gPay => tr('GPay'),
      PaymentMode.bank => tr('Bank'),
    };

/// Payment mode chips (PRD KH-01).
class PaymentModeChips extends StatelessWidget {
  const PaymentModeChips({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PaymentMode value;
  final ValueChanged<PaymentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSizes.gap,
      runSpacing: AppSizes.gap,
      children: [
        for (final mode in PaymentMode.values)
          ChoiceChip(
            label: Text(paymentModeLabel(mode)),
            selected: value == mode,
            onSelected: (_) => onChanged(mode),
          ),
      ],
    );
  }
}

Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initial,
  DateTime? first,
  DateTime? last,
}) {
  final lastDate = last ?? DateTime.now().add(const Duration(days: 365));
  final firstDate = first ?? DateTime(2000);
  var initialDate = initial;
  if (initialDate.isAfter(lastDate)) initialDate = lastDate;
  if (initialDate.isBefore(firstDate)) initialDate = firstDate;
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
  );
}
