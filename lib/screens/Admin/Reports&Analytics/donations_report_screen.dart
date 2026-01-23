import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/utils/file_download_helper.dart';
import 'package:ration_aid/theme/app_colors.dart';

class DonationsReportScreen extends StatefulWidget {
  const DonationsReportScreen({super.key});

  @override
  State<DonationsReportScreen> createState() => _DonationsReportScreenState();
}

class _DonationsReportScreenState extends State<DonationsReportScreen> {
  @override
  void initState() {
    super.initState();
    _logReportView();
  }

  Future<void> _logReportView() async {
    await AuditService.logSystemAction(
      action: 'Donations Report viewed',
      details: 'Admin accessed donations analytics and report',
    );
  }

  Future<Map<String, dynamic>> _loadDonationsSummary() async {
    final donationsRef = FirebaseFirestore.instance.collection('donations');

    // Status counts
    final totalAgg = await donationsRef.count().get();
    final verifiedAgg = await donationsRef
        .where('status', isEqualTo: 'verified')
        .count()
        .get();
    final pendingAgg = await donationsRef
        .where('status', isEqualTo: 'pending')
        .count()
        .get();
    final underReviewAgg = await donationsRef
        .where('status', isEqualTo: 'under_review')
        .count()
        .get();
    final rejectedAgg = await donationsRef
        .where('status', isEqualTo: 'rejected')
        .count()
        .get();

    final totalDonations = totalAgg.count ?? 0;
    final verified = verifiedAgg.count ?? 0;
    final pending = pendingAgg.count ?? 0;
    final underReview = underReviewAgg.count ?? 0;
    final rejected = rejectedAgg.count ?? 0;

    // Get all donations for amount calculations
    final allDonations = await donationsRef.get();

    double totalAmount = 0;
    double verifiedAmount = 0;
    double pendingAmount = 0;
    final Map<String, double> donorAmounts = {};
    final Map<String, int> donorCounts = {};

    for (final doc in allDonations.docs) {
      final data = doc.data();
      final amount = (data['amount'] ?? 0).toDouble();
      final status = data['status'] ?? 'pending';
      final donorName = data['donorName'] ?? 'Anonymous';

      totalAmount += amount;

      if (status == 'verified') {
        verifiedAmount += amount;
      } else if (status == 'pending' || status == 'under_review') {
        pendingAmount += amount;
      }

      donorAmounts[donorName] = (donorAmounts[donorName] ?? 0) + amount;
      donorCounts[donorName] = (donorCounts[donorName] ?? 0) + 1;
    }

    // Top 5 donors
    final sortedDonors = donorAmounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topDonors = sortedDonors
        .take(5)
        .map(
          (e) => {
            'name': e.key,
            'amount': e.value,
            'count': donorCounts[e.key] ?? 0,
          },
        )
        .toList();

    // Recent donations (last 7 days)
    final now = DateTime.now();
    final cutoff7 = now.subtract(const Duration(days: 7));
    int recentDonations = 0;

    for (final doc in allDonations.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt != null && createdAt.toDate().isAfter(cutoff7)) {
        recentDonations++;
      }
    }

    return {
      'totalDonations': totalDonations,
      'verified': verified,
      'pending': pending,
      'underReview': underReview,
      'rejected': rejected,
      'totalAmount': totalAmount,
      'verifiedAmount': verifiedAmount,
      'pendingAmount': pendingAmount,
      'topDonors': topDonors,
      'recentDonations': recentDonations,
    };
  }

  Future<void> _exportReport() async {
    try {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Generating report...')));

      final data = await _loadDonationsSummary();

      final csvContent = StringBuffer();

      csvContent.writeln('Ration Aid - Donations Report');
      csvContent.writeln('Generated on: ${DateTime.now()}');
      csvContent.writeln('');

      csvContent.writeln('OVERVIEW');
      csvContent.writeln('Metric,Value');
      csvContent.writeln('Total Donations,${data['totalDonations']}');
      csvContent.writeln('Total Amount,${data['totalAmount']} PKR');
      csvContent.writeln('Verified Amount,${data['verifiedAmount']} PKR');
      csvContent.writeln('Pending Amount,${data['pendingAmount']} PKR');
      csvContent.writeln('Recent (7 days),${data['recentDonations']}');
      csvContent.writeln('');

      csvContent.writeln('STATUS BREAKDOWN');
      csvContent.writeln('Status,Count');
      csvContent.writeln('Verified,${data['verified']}');
      csvContent.writeln('Pending,${data['pending']}');
      csvContent.writeln('Under Review,${data['underReview']}');
      csvContent.writeln('Rejected,${data['rejected']}');
      csvContent.writeln('');

      csvContent.writeln('TOP DONORS');
      csvContent.writeln('Donor Name,Total Amount,Donation Count');
      final topDonors = data['topDonors'] as List;
      for (final donor in topDonors) {
        csvContent.writeln(
          '${donor['name']},${donor['amount']},${donor['count']}',
        );
      }
      csvContent.writeln('');

      // Detailed Donation Data Section
      csvContent.writeln('DETAILED DONATION DATA');
      csvContent.writeln(
        'Donation ID,Donor Name,Donor Email,Amount (PKR),Status,Payment Method,Description,Donation Date,Verified Date,Verified By',
      );

      // Fetch all donations
      final donationsSnapshot = await FirebaseFirestore.instance
          .collection('donations')
          .get();

      for (final doc in donationsSnapshot.docs) {
        final donationData = doc.data();
        final donationId = doc.id;
        final donorName = donationData['donorName'] ?? 'Anonymous';
        final donorEmail = donationData['donorEmail'] ?? 'N/A';
        final amount = donationData['amount'] ?? 0;
        final status = donationData['status'] ?? 'pending';
        final paymentMethod = donationData['paymentMethod'] ?? 'N/A';
        final description = donationData['description'] ?? 'N/A';

        final createdAt = donationData['createdAt'] as Timestamp?;
        final createdAtStr = createdAt != null
            ? createdAt.toDate().toString().split('.')[0]
            : 'N/A';

        final verifiedAt = donationData['verifiedAt'] as Timestamp?;
        final verifiedAtStr = verifiedAt != null
            ? verifiedAt.toDate().toString().split('.')[0]
            : 'N/A';

        final verifiedBy = donationData['verifiedBy'] ?? 'N/A';

        // Escape commas in fields for CSV
        csvContent.writeln(
          '"$donationId","$donorName","$donorEmail",$amount,$status,"$paymentMethod","$description","$createdAtStr","$verifiedAtStr","$verifiedBy"',
        );
      }

      final filePath = await FileDownloadHelper.downloadCsvFile(
        filename:
            'Donations_Report_${DateTime.now().millisecondsSinceEpoch}.csv',
        csvContent: csvContent.toString(),
      );

      await AuditService.logSystemAction(
        action: 'Donations Report exported',
        details:
            'Admin successfully exported donations report as CSV to $filePath',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Report saved to Downloads folder!\nFile: ${filePath.split('/').last}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Donations report',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.primaryBlue : Colors.white,
          ),
        ),
        backgroundColor: isDark ? Colors.grey[900] : AppColors.primaryBlue,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export report',
            onPressed: _exportReport,
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _loadDonationsSummary(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return Center(
              child: Text(
                'No donation data available.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final totalDonations = data['totalDonations'] as int;
          final verified = data['verified'] as int;
          final pending = data['pending'] as int;
          final underReview = data['underReview'] as int;
          final rejected = data['rejected'] as int;
          final totalAmount = data['totalAmount'] as double;
          final verifiedAmount = data['verifiedAmount'] as double;
          final topDonors = data['topDonors'] as List;
          final recentDonations = data['recentDonations'] as int;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Centered header
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Donations analytics',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Financial contributions and verification status overview.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Overview
                _sectionTitle('Overview'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.volunteer_activism,
                        title: 'Total donations',
                        value: totalDonations.toString(),
                        subtitle: 'All contributions',
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.currency_rupee,
                        title: 'Total amount',
                        value: '${totalAmount.toStringAsFixed(0)} PKR',
                        subtitle: 'Received',
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.verified,
                        title: 'Verified',
                        value: '${verifiedAmount.toStringAsFixed(0)} PKR',
                        subtitle: '$verified donations',
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.schedule,
                        title: 'New (7d)',
                        value: recentDonations.toString(),
                        subtitle: 'Recent donations',
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Status breakdown
                _sectionTitle('Status breakdown'),
                const SizedBox(height: 12),
                Card(
                  elevation: 2,
                  color: theme.cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _statusRow(
                          'Verified',
                          verified,
                          totalDonations,
                          Colors.green,
                        ),
                        const Divider(height: 16),
                        _statusRow(
                          'Pending',
                          pending,
                          totalDonations,
                          Colors.orange,
                        ),
                        const Divider(height: 16),
                        _statusRow(
                          'Under review',
                          underReview,
                          totalDonations,
                          Colors.blue,
                        ),
                        const Divider(height: 16),
                        _statusRow(
                          'Rejected',
                          rejected,
                          totalDonations,
                          Colors.red,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Top donors
                _sectionTitle('Top donors'),
                const SizedBox(height: 12),
                if (topDonors.isEmpty)
                  Card(
                    elevation: 2,
                    color: theme.cardColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No donations recorded yet.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  )
                else
                  ...topDonors.asMap().entries.map((entry) {
                    final index = entry.key;
                    final donor = entry.value;
                    return Card(
                      elevation: 1,
                      color: theme.cardColor,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.amber.withOpacity(0.2),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                        title: Text(
                          donor['name'],
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          '${donor['count']} donations',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        trailing: Text(
                          '${(donor['amount'] as double).toStringAsFixed(0)} PKR',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, int count, int total, Color color) {
    final theme = Theme.of(context);
    final percentage = total > 0
        ? (count / total * 100).toStringAsFixed(1)
        : '0.0';
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
          ),
        ),
        Expanded(
          flex: 3,
          child: LinearProgressIndicator(
            value: total > 0 ? count / total : 0,
            backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$count ($percentage%)',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}
