import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/db/database.dart';
import '../../../core/pdf/pdf_common.dart';
import '../../../core/utils/dates.dart';

final _pdfDate = DateFormat('d MMM yyyy');

/// Pay-slip for one settlement (PRD KH-09).
Future<Uint8List> buildPayslipPdf({
  required BusinessProfile profile,
  required Worker worker,
  required Settlement settlement,
  String? roleName,
}) async {
  final from = _pdfDate.format(parseIsoDate(settlement.periodFrom));
  final to = _pdfDate.format(parseIsoDate(settlement.periodTo));
  final net = settlement.paidPaise + settlement.carryForwardPaise;

  final pdf = pw.Document(title: 'Pay slip ${worker.name}');
  pdf.addPage(
    pw.Page(
      pageFormat: pdfPageFormat,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pdfBusinessHeader(profile, label: 'PAY SLIP'),
          pw.SizedBox(height: 20),
          pw.Text(worker.name, style: pdfBold),
          if (roleName != null) pw.Text(roleName),
          pw.Text('Period: $from to $to'),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pdfBorder,
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
            },
            children: [
              _row('Earning (wages, OT, piece work, bonus)',
                  pdfMoney(settlement.earningPaise)),
              _row('Advance taken', '- ${pdfMoney(settlement.advancePaise)}'),
              if (settlement.emiPaise != 0)
                _row('Loan EMI', '- ${pdfMoney(settlement.emiPaise)}'),
              _row('Net payable (incl. previous balance)', pdfMoney(net),
                  bold: true),
              _row('Paid', pdfMoney(settlement.paidPaise), bold: true),
              _row(
                settlement.carryForwardPaise >= 0
                    ? 'Balance carried forward (to worker)'
                    : 'Balance carried forward (worker owes)',
                pdfMoney(settlement.carryForwardPaise.abs()),
              ),
            ],
          ),
          pw.Spacer(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Worker signature'),
              pw.Text('For ${profile.name}'),
            ],
          ),
        ],
      ),
    ),
  );
  return pdf.save();
}

pw.TableRow _row(String label, String value, {bool bold = false}) =>
    pw.TableRow(children: [
      pdfCell(label, bold: bold),
      pdfCell(value, bold: bold, align: pw.TextAlign.right),
    ]);
