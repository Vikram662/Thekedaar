final _upiIdPattern = RegExp(r'^[A-Za-z0-9._-]{2,256}@[A-Za-z][A-Za-z0-9.]{1,63}$');

/// `name@bank` style VPA, e.g. `ramesh.electric@okaxis`.
bool isValidUpiId(String value) => _upiIdPattern.hasMatch(value.trim());

/// UPI deep link (NPCI spec) that opens any UPI app with the payee, amount
/// and note filled in (PRD KH-08, BL-11). Amount is optional: without it the
/// payer types the amount.
String upiPayUri({
  required String upiId,
  required String payeeName,
  int? amountPaise,
  String? note,
}) {
  final params = <String, String>{
    'pa': upiId.trim(),
    'pn': payeeName.trim(),
    if (amountPaise != null && amountPaise > 0)
      'am': _amount(amountPaise),
    'cu': 'INR',
    if (note != null && note.trim().isNotEmpty) 'tn': note.trim(),
  };
  // UPI apps expect %20 for spaces, not '+'.
  final query = params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return 'upi://pay?$query';
}

/// 12345 → "123.45", 60000 → "600.00" (UPI wants two decimals).
String _amount(int paise) =>
    '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';
