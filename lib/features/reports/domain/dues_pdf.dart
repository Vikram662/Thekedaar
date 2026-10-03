import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/db/database.dart';
import '../../../core/pdf/pdf_common.dart';
import 'dues_report.dart';

/// Lena / Dena report as a PDF to keep or share.
Future<Uint8List> buildDuesPdf(DuesReport report, BusinessProfile profile) {
  final pdf = pw.Document(title: 'Lena Dena report');
  final date = DateFormat('d MMM yyyy, h:mm a').format(DateTime.now());

  pw.Widget table(String title, List<DueItem> items, int total,
      {bool showOverdue = false}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pdfBold),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pdfBorder,
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(1.5),
            if (showOverdue) 2: const pw.FlexColumnWidth(2),
            (showOverdue ? 3 : 2): const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(children: [
              pdfCell('Name', bold: true),
              pdfCell('Type', bold: true),
              if (showOverdue)
                pdfCell('Overdue', bold: true, align: pw.TextAlign.right),
              pdfCell('Amount', bold: true, align: pw.TextAlign.right),
            ]),
            for (final item in items)
              pw.TableRow(children: [
                pdfCell(item.name),
                pdfCell(item.party == DueParty.client ? 'Client' : 'Worker'),
                if (showOverdue)
                  pdfCell(
                    item.overduePaise == 0 ? '-' : pdfMoney(item.overduePaise),
                    align: pw.TextAlign.right,
                  ),
                pdfCell(pdfMoney(item.amountPaise), align: pw.TextAlign.right),
              ]),
          ],
        ),
        pw.SizedBox(height: 6),
        pdfTotalRow('Total', pdfMoney(total), bold: true),
      ],
    );
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: pdfPageFormat,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pdfBusinessHeader(profile, label: 'LENA / DENA'),
        pw.SizedBox(height: 8),
        pw.Text('As on $date', style: pdfSmall),
        pw.SizedBox(height: 16),
        table('To receive (Lena)', report.lena, report.lenaTotal,
            showOverdue: true),
        pw.SizedBox(height: 20),
        table('To pay (Dena)', report.dena, report.denaTotal),
      ],
    ),
  );
  return pdf.save();
}
