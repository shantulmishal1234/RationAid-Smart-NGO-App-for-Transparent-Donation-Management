import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:flutter/material.dart';

class ReportCsvService {
  static Future<void> generateAndOpenReport(
    List<ProcurementRequest> requests,
    DateTimeRange? range,
  ) async {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('HH:mm');

    List<List<dynamic>> rows = [];

    // Header Info
    rows.add(["Ration Aid - Procurement Report"]);
    rows.add([
      "Generated On",
      "${dateFormat.format(DateTime.now())} ${timeFormat.format(DateTime.now())}",
    ]);
    if (range != null) {
      rows.add([
        "Period",
        "${dateFormat.format(range.start)} to ${dateFormat.format(range.end)}",
      ]);
    } else {
      rows.add(["Period", "All Time"]);
    }
    rows.add([]); // Blank line

    // Summary
    final totalSpent = requests.fold<double>(0, (sum, r) => sum + r.totalSpent);
    rows.add(["Total Records", requests.length]);
    rows.add(["Total Value (Rs)", totalSpent.toStringAsFixed(2)]);
    rows.add([]); // Blank line

    // Column Headers
    rows.add([
      "Date",
      "Pack Name",
      "Budget Limit",
      "Total Spent",
      "Status",
      "Admin Remarks",
      "Items Count",
    ]);

    // Data Rows
    for (var r in requests) {
      rows.add([
        dateFormat.format(r.verifiedAt ?? r.createdAt),
        r.packName,
        r.budgetLimit,
        r.totalSpent,
        r.status.toString().split('.').last.toUpperCase(),
        r.adminRemarks ?? "",
        r.items.length,
      ]);
    }

    // Convert to CSV
    String csvData = const ListToCsvConverter().convert(rows);

    // Save and Open
    final output = await getTemporaryDirectory();
    final fileName =
        "procurement_report_${DateTime.now().millisecondsSinceEpoch}.csv";
    final file = File("${output.path}/$fileName");

    await file.writeAsString(csvData);
    await OpenFile.open(file.path);
  }
}
