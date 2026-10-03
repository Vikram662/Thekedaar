import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../db/database.dart';
import '../utils/money.dart';
import '../utils/phone.dart';
import '../utils/photo_store.dart';

pw.ThemeData? _pdfTheme;
var _hasRupeeGlyph = false;

/// Noto Sans (bundled in assets/fonts) so PDFs can print ₹. Pass it to every
/// `pw.Document(theme: ...)`. If the fonts cannot be loaded, PDFs fall back
/// to the built-in Helvetica, which has no ₹, and [pdfMoney] prints "Rs.".
Future<pw.ThemeData?> pdfTheme() async {
  if (_pdfTheme != null) return _pdfTheme;
  try {
    final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    _pdfTheme = pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
    _hasRupeeGlyph = true;
  } catch (_) {
    _hasRupeeGlyph = false;
  }
  return _pdfTheme;
}

String pdfMoney(int paise) => _hasRupeeGlyph
    ? formatPaise(paise)
    : formatPaise(paise).replaceAll('₹', 'Rs. ');

final pdfBorder = pw.TableBorder.all(width: 0.5, color: PdfColors.grey600);

const pdfSmall = pw.TextStyle(fontSize: 9, color: PdfColors.grey800);
final pdfBold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
final pdfTitle = pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold);

/// The business logo for PDFs, or null if none is set or it can't be read.
Future<pw.ImageProvider?> pdfLogo(BusinessProfile profile) async {
  final name = profile.logoPath;
  if (name == null) return null;
  try {
    final file = await photoFile(name);
    if (!file.existsSync()) return null;
    return pw.MemoryImage(await file.readAsBytes());
  } catch (_) {
    return null;
  }
}

/// Logo, business name, phone and address block for the top of every PDF.
pw.Widget pdfBusinessHeader(
  BusinessProfile profile, {
  required String label,
  pw.ImageProvider? logo,
}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (logo != null) ...[
        pw.Container(
          width: 64,
          height: 64,
          alignment: pw.Alignment.center,
          child: pw.Image(logo, fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(width: 12),
      ],
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(profile.name, style: pdfTitle),
            if (profile.phone != null)
              pw.Text('Phone: ${formatIndianPhone(profile.phone!)}'),
            if (profile.address != null && profile.address!.isNotEmpty)
              pw.Text(profile.address!, style: pdfSmall),
          ],
        ),
      ),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
        child: pw.Text(label, style: pdfBold),
      ),
    ],
  );
}

pw.Widget pdfCell(
  String text, {
  pw.TextAlign align = pw.TextAlign.left,
  bool bold = false,
}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        textAlign: align,
        style: bold ? pdfBold : null,
      ),
    );

pw.Widget pdfTotalRow(String label, String value, {bool bold = false}) =>
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.SizedBox(
          width: 120,
          child: pw.Text(label, style: bold ? pdfBold : null),
        ),
        pw.SizedBox(
          width: 100,
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: bold ? pdfBold : null,
          ),
        ),
      ],
    );

/// Writes the PDF to the temp folder and opens the share sheet, so the PDF
/// file itself goes to WhatsApp (PRD I-B5, BL-12).
Future<void> sharePdf(
  Uint8List bytes, {
  required String fileName,
  String? text,
}) async {
  final dir = await getTemporaryDirectory();
  final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
  final file = File(p.join(dir.path, safeName));
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: text),
  );
}

PdfPageFormat get pdfPageFormat => PdfPageFormat.a4;
