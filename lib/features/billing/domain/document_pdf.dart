import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/pdf/pdf_common.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/utils/qty.dart';
import '../../../core/utils/upi.dart';
import '../data/billing_repository.dart';

final _pdfDate = DateFormat('d MMM yyyy', 'en');

/// Non-tax quotation / bill PDF (PRD BL-02, BL-11, I-B1).
Future<Uint8List> buildDocumentPdf(
  DocumentDetail detail,
  BusinessProfile profile,
) async {
  final doc = detail.document;
  final isInvoice = doc.kind == DocumentKind.invoice;
  final label = isInvoice ? 'BILL (NON-TAX)' : 'ESTIMATE / QUOTATION';
  final rawUpi = profile.upiId?.trim();
  final upiId = rawUpi != null && isValidUpiId(rawUpi) ? rawUpi : null;

  final logo = await pdfLogo(profile);
  final pdf = pw.Document(
    title: doc.number,
    author: profile.name,
    theme: await pdfTheme(),
  );
  pdf.addPage(
    pw.MultiPage(
      pageFormat: pdfPageFormat,
      margin: const pw.EdgeInsets.all(32),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Estimate, not a tax invoice.', style: pdfSmall),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pdfSmall,
          ),
        ],
      ),
      build: (context) => [
        pdfBusinessHeader(profile, label: label, logo: logo),
        pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('To', style: pdfSmall),
                  pw.Text(detail.client.name, style: pdfBold),
                  if (detail.client.phone != null)
                    pw.Text(formatIndianPhone(detail.client.phone!)),
                  if (detail.client.address != null &&
                      detail.client.address!.isNotEmpty)
                    pw.Text(detail.client.address!),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('No: ${doc.number}'
                    '${doc.revision > 1 ? '  (Rev ${doc.revision})' : ''}'),
                pw.Text('Date: ${_pdfDate.format(parseIsoDate(doc.date))}'),
                if (doc.dueDate != null)
                  pw.Text(
                      'Due: ${_pdfDate.format(parseIsoDate(doc.dueDate!))}'),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pdfBorder,
          columnWidths: const {
            0: pw.FixedColumnWidth(24),
            1: pw.FlexColumnWidth(5),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(2),
            4: pw.FlexColumnWidth(2.4),
          },
          children: [
            pw.TableRow(children: [
              pdfCell('#', bold: true),
              pdfCell('Description', bold: true),
              pdfCell('Qty', bold: true, align: pw.TextAlign.right),
              pdfCell('Rate', bold: true, align: pw.TextAlign.right),
              pdfCell('Amount', bold: true, align: pw.TextAlign.right),
            ]),
            for (var i = 0; i < detail.lines.length; i++)
              _lineRow(i + 1, detail.lines[i]),
          ],
        ),
        pw.SizedBox(height: 12),
        pdfTotalRow('Subtotal', pdfMoney(doc.subtotalPaise)),
        if (doc.discountPaise != 0)
          pdfTotalRow(
            doc.discountPercentBp == null
                ? 'Discount'
                : 'Discount (${formatScaledPercent(doc.discountPercentBp!)}%)',
            '- ${pdfMoney(doc.discountPaise)}',
          ),
        if (doc.roundOffPaise != 0)
          pdfTotalRow('Round off', pdfMoney(doc.roundOffPaise)),
        pw.Divider(),
        pdfTotalRow('Total', pdfMoney(doc.totalPaise), bold: true),
        if (isInvoice && detail.paidPaise > 0) ...[
          pdfTotalRow('Received', pdfMoney(detail.paidPaise)),
          pdfTotalRow('Balance due', pdfMoney(detail.balancePaise), bold: true),
        ],
        if (upiId != null) ...[
          pw.SizedBox(height: 12),
          _upiBlock(
            upiId: upiId,
            payee: profile.name,
            // Bills: QR carries the amount still due (PRD BL-11).
            amountPaise: isInvoice ? detail.balancePaise : null,
            note: doc.number,
          ),
        ],
        if (doc.notes != null && doc.notes!.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text('Notes', style: pdfBold),
          pw.Text(doc.notes!),
        ],
        if (doc.terms != null && doc.terms!.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text('Terms & Conditions', style: pdfBold),
          for (final line in doc.terms!.split('\n'))
            if (line.trim().isNotEmpty) pw.Text('- ${line.trim()}'),
        ],
        pw.SizedBox(height: 40),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('For ${profile.name}'),
        ),
      ],
    ),
  );
  return pdf.save();
}

/// UPI QR + id. Scanning it in any UPI app fills payee, amount and bill no.
pw.Widget _upiBlock({
  required String upiId,
  required String payee,
  required int? amountPaise,
  required String note,
}) {
  final hasAmount = amountPaise != null && amountPaise > 0;
  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.5, color: PdfColors.grey600),
    ),
    child: pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: upiPayUri(
            upiId: upiId,
            payeeName: payee,
            amountPaise: hasAmount ? amountPaise : null,
            note: note,
          ),
          width: 84,
          height: 84,
        ),
        pw.SizedBox(width: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Scan to pay with any UPI app', style: pdfBold),
            pw.SizedBox(height: 4),
            pw.Text('UPI ID: $upiId'),
            if (hasAmount) pw.Text('Amount: ${pdfMoney(amountPaise)}'),
          ],
        ),
      ],
    ),
  );
}

pw.TableRow _lineRow(int index, LineWithUnit row) {
  final line = row.line;
  final unit = row.unitCode ?? '';
  final measurement = row.measurement;
  return pw.TableRow(children: [
    pdfCell('$index'),
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(line.name),
          for (final m in measurement)
            pw.Text(
              '${m.isDeduction ? 'Less ' : ''}${m.label.isEmpty ? '' : '${m.label}: '}'
              '${m.nos > 1 ? '${m.nos} x ' : ''}${formatMilli(m.lengthMilli)}'
              '${m.widthMilli == null ? '' : ' x ${formatMilli(m.widthMilli!)}'}'
              '${m.heightMilli == null ? '' : ' x ${formatMilli(m.heightMilli!)}'}'
              ' = ${formatMilli(m.qtyMilli)}',
              style: pdfSmall,
            ),
        ],
      ),
    ),
    pdfCell('${formatMilli(line.qtyMilli)} $unit'.trim(),
        align: pw.TextAlign.right),
    pdfCell(pdfMoney(line.ratePaise), align: pw.TextAlign.right),
    pdfCell(pdfMoney(line.amountPaise), align: pw.TextAlign.right),
  ]);
}

/// 1250 → "12.5".
String formatScaledPercent(int basisPoints) =>
    paiseToInputText(basisPoints);
