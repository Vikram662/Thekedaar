import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../data/billing_repository.dart';

/// PRD BL-01: client name, phone, address.
class ClientFormScreen extends ConsumerStatefulWidget {
  const ClientFormScreen({super.key, this.clientId});

  final String? clientId;

  @override
  ConsumerState<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends ConsumerState<ClientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final address = _address.text.trim();
    await ref.read(billingRepositoryProvider).saveClient(
          id: widget.clientId,
          name: _name.text.trim(),
          phone: normalizeIndianPhone(_phone.text),
          address: address.isEmpty ? null : address,
        );
    if (!mounted) return;
    showMessage(context, 'Client saved');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.clientId != null && !_loaded) {
      final client = ref.watch(clientProvider(widget.clientId!)).valueOrNull;
      if (client == null) {
        return const SkeletonPage();
      }
      _loaded = true;
      _name.text = client.client.name;
      _phone.text = client.client.phone == null
          ? ''
          : formatIndianPhone(client.client.phone!);
      _address.text = client.client.address ?? '';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clientId == null ? 'New Client' : 'Edit Client'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile number (optional)',
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
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Address (optional)'),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          BottomActionBar(label: 'Save', busy: _saving, onPressed: _save),
    );
  }
}
