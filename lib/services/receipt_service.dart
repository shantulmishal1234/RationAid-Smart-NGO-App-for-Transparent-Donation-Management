import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/models/donation_model.dart';

/// Service to generate donation receipt PDFs
class ReceiptService {
  /// Generate and open a donation receipt PDF
  static Future<bool> generateReceipt(Donation donation) async {
    try {
      final pdf = pw.Document();

      final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
      final currencyFormat = NumberFormat.currency(
        symbol: 'Rs. ',
        decimalDigits: 0,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(20),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#2E7D32'),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'RATION AID',
                        style: pw.TextStyle(
                          fontSize: 28,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Donation Receipt',
                        style: const pw.TextStyle(
                          fontSize: 16,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 30),

                // Receipt Info Box
                pw.Container(
                  padding: const pw.EdgeInsets.all(20),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(
                        'Receipt No',
                        donation.id.substring(0, 8).toUpperCase(),
                      ),
                      pw.Divider(height: 20, color: PdfColors.grey200),
                      _buildInfoRow(
                        'Date',
                        dateFormat.format(donation.createdAt),
                      ),
                      pw.Divider(height: 20, color: PdfColors.grey200),
                      _buildInfoRow(
                        'Type',
                        donation.donationType == DonationType.cash
                            ? 'Cash Donation'
                            : 'In-Kind Donation',
                      ),
                      pw.Divider(height: 20, color: PdfColors.grey200),
                      _buildInfoRow(
                        'Status',
                        donation.status.displayName.toUpperCase(),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),

                // Donation Details
                pw.Text(
                  'Donation Details',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),

                pw.Container(
                  padding: const pw.EdgeInsets.all(20),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F5F5F5'),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (donation.donationType == DonationType.cash) ...[
                        _buildInfoRow(
                          'Amount',
                          currencyFormat.format(donation.amount ?? 0),
                        ),
                      ] else ...[
                        if (donation.items != null &&
                            donation.items!.isNotEmpty) ...[
                          pw.Text(
                            'Items Donated:',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          ...donation.items!.entries.map(
                            (item) => pw.Padding(
                              padding: const pw.EdgeInsets.only(bottom: 4),
                              child: pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('• ${item.key}'),
                                  pw.Text('x${item.value}'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),

                // Family Info (masked)
                if (donation.familyId.isNotEmpty) ...[
                  pw.Text(
                    'Recipient Family',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow(
                          'Family ID',
                          '****${donation.familyId.substring(donation.familyId.length - 4)}',
                        ),
                      ],
                    ),
                  ),
                ],

                pw.Spacer(),

                // Footer
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#E8F5E9'),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'Thank you for your generous donation!',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#2E7D32'),
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Your contribution helps families in need.',
                        style: const pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.grey700,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

      // Save PDF
      final output = await getTemporaryDirectory();
      final file = File(
        '${output.path}/Receipt_${donation.id.substring(0, 8)}.pdf',
      );
      await file.writeAsBytes(await pdf.save());

      // Open PDF
      await OpenFile.open(file.path);

      return true;
    } catch (e) {
      return false;
    }
  }

  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700)),
        pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ],
    );
  }
}
