import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/i18n/i18n.dart';
import '../../core/security/pin.dart';

/// 4 dots + large numpad (PRD AU-02). Calls [onCompleted] with the PIN.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onCompleted,
    this.enabled = true,
    this.onBiometric,
  });

  final Future<void> Function(String pin) onCompleted;
  final bool enabled;
  final VoidCallback? onBiometric;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;

  void clear() => setState(() => _pin = '');

  Future<void> _press(String digit) async {
    if (!widget.enabled || _busy || _pin.length >= pinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length == pinLength) {
      setState(() => _busy = true);
      try {
        await widget.onCompleted(_pin);
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _pin = '';
          });
        }
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: tr('{count} of {pinLength} digits entered', {'count': _pin.length, 'pinLength': pinLength}),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pinLength; i++)
                Container(
                  margin: const EdgeInsets.all(10),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? AppColors.slate900 : null,
                    border: Border.all(color: AppColors.slate900, width: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          _row([for (final d in row) _digit(d)]),
        _row([
          widget.onBiometric == null
              ? const SizedBox(width: 72, height: 72)
              : _iconKey(Icons.fingerprint, tr('Use fingerprint'), widget.onBiometric!),
          _digit('0'),
          _iconKey(Icons.backspace_outlined, tr('Delete'), _backspace),
        ]),
      ],
    );
  }

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: children,
        ),
      );

  Widget _digit(String digit) => SizedBox(
        width: 72,
        height: 72,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            foregroundColor: AppColors.slate900,
          ),
          onPressed: widget.enabled ? () => _press(digit) : null,
          child: Text(
            digit,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
        ),
      );

  Widget _iconKey(IconData icon, String label, VoidCallback onTap) => SizedBox(
        width: 72,
        height: 72,
        child: IconButton(
          iconSize: 30,
          tooltip: label,
          onPressed: widget.enabled ? onTap : null,
          icon: Icon(icon),
        ),
      );
}
