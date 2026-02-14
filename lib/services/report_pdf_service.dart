import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart'; // For DateTimeRange

class ReportPdfService {
  static Future<void> generateAndOpenReport(
    List<ProcurementRequest> requests,
    DateTimeRange? range,
  ) async {
    final pdf = pw.Document();

    // Calculate totals
    final totalSpent = requests.fold<double>(0, (sum, r) => sum + r.totalSpent);
    final count = requests.length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Ration Aid',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange,
                  ),
                ),
                pw.Text(
                  'Procurement Report',
                  style: pw.TextStyle(fontSize: 18, color: PdfColors.grey700),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Generated On: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
                  ),
                  if (range != null)
                    pw.Text(
                      'Period: ${DateFormat('MMM dd').format(range.start)} - ${DateFormat('MMM dd, yyyy').format(range.end)}',
                    ),
                  if (range == null) pw.Text('Period: All Time'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Total Records: $count'),
                  pw.Text(
                    'Total Value: Rs ${totalSpent.toStringAsFixed(0)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),

          pw.Divider(),
          pw.SizedBox(height: 20),

          pw.Text(
            'Transaction Log',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),

          pw.Table.fromTextArray(
            headers: ['Date', 'Pack Name', 'Amount (Rs)', 'Status'],
            data: requests
                .map(
                  (r) => [
                    DateFormat(
                      'yyyy-MM-dd',
                    ).format(r.verifiedAt ?? r.createdAt),
                    r.packName,
                    r.totalSpent.toStringAsFixed(0),
                    r.status.toString().split('.').last.toUpperCase(),
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.orange),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300),
              ),
            ),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.center,
            },
          ),

          pw.SizedBox(height: 30),
          pw.Footer(
            leading: pw.Text(
              'Confidential Report',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
            trailing: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File(
      "${output.path}/procurement_report_${DateTime.now().millisecondsSinceEpoch}.pdf",
    );
    await file.writeAsBytes(await pdf.save());

    await OpenFile.open(file.path);
  }
}
