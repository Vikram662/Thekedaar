import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/providers.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';

/// Name, phone, address, UPI and number prefixes shown on PDFs (PRD BL-11).
class BusinessProfileScreen extends ConsumerStatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  ConsumerState<BusinessProfileScreen> createState() =>
      _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _upi = TextEditingController();
  final _invoicePrefix = TextEditingController();
  final _quotationPrefix = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _upi, _invoicePrefix, _quotationPrefix]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    String? opt(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    await ref.read(settingsRepositoryProvider).saveProfile(
          name: _name.text.trim(),
          phone: normalizeIndianPhone(_phone.text),
          address: opt(_address),
          upiId: opt(_upi),
          invoicePrefix: _invoicePrefix.text.trim().toUpperCase(),
          quotationPrefix: _quotationPrefix.text.trim().toUpperCase(),
        );
    if (!mounted) return;
    showMessage(context, 'Saved');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_loaded) {
      _loaded = true;
      _name.text = profile.name;
      _phone.text = profile.phone == null ? '' : formatIndianPhone(profile.phone!);
      _address.text = profile.address ?? '';
      _upi.text = profile.upiId ?? '';
      _invoicePrefix.text = profile.invoicePrefix;
      _quotationPrefix.text = profile.quotationPrefix;
    }
    String? requiredField(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Required' : null;
    String? prefix(String? v) =>
        (v == null || !RegExp(r'^[A-Za-z0-9]{1,6}$').hasMatch(v.trim()))
            ? '1–6 letters or digits'
            : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Business profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Business name'),
              validator: requiredField,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                prefixText: '+91 ',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty || normalizeIndianPhone(v) != null)
                      ? null
                      : 'Enter a valid 10-digit mobile number',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _upi,
              decoration: const InputDecoration(
                labelText: 'UPI ID (printed on bills)',
                hintText: 'name@bank',
              ),
            ),
            const SectionTitle('Numbering'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _invoicePrefix,
                    decoration: const InputDecoration(labelText: 'Bill prefix'),
                    validator: prefix,
                  ),
                ),
                const SizedBox(width: AppSizes.gap),
                Expanded(
                  child: TextFormField(
                    controller: _quotationPrefix,
                    decoration:
                        const InputDecoration(labelText: 'Quotation prefix'),
                    validator: prefix,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Numbers restart every financial year, e.g. INV/26-27/0001.',
              style: TextStyle(color: AppColors.slate600),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          BottomActionBar(label: 'Save', busy: _saving, onPressed: _save),
    );
  }
}
