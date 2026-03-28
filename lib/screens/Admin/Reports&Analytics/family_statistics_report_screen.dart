import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/utils/file_download_helper.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';

class FamilyStatisticsReportScreen extends StatefulWidget {
  const FamilyStatisticsReportScreen({super.key});

  @override
  State<FamilyStatisticsReportScreen> createState() =>
      _FamilyStatisticsReportScreenState();
}

class _FamilyStatisticsReportScreenState
    extends State<FamilyStatisticsReportScreen> {
  @override
  void initState() {
    super.initState();
    _logReportView();
  }

  Future<void> _logReportView() async {
    await AuditService.logSystemAction(
      action: 'Family Statistics Report viewed',
      details: 'Admin accessed family/household analytics report',
    );
  }

  Map<String, dynamic> _computeStatistics(QuerySnapshot allFamilies) {
    int totalFamilies = allFamilies.docs.length;
    int accepted = 0;
    int pending = 0;
    int rejected = 0;
    int discarded = 0;

    final Map<String, int> areaDistribution = {};
    int totalMembers = 0;
    int recentApplications = 0;

    final now = DateTime.now();
    final cutoff7 = now.subtract(const Duration(days: 7));

    for (final doc in allFamilies.docs) {
      final data = doc.data() as Map<String, dynamic>;

      final status = data['status'] as String?;
      if (status == 'accepted') {
        accepted++;
      } else if (status == 'pending')
        pending++;
      else if (status == 'rejected')
        rejected++;
      else if (status == 'discarded')
        discarded++;

      final area = (data['area'] ?? 'Unknown').toString();
      final members = (data['familySize'] ?? 0) as int;
      final createdAt = data['createdAt'] as Timestamp?;

      areaDistribution[area] = (areaDistribution[area] ?? 0) + 1;
      totalMembers += members;
      if (createdAt != null && createdAt.toDate().isAfter(cutoff7)) {
        recentApplications++;
      }
    }

    // Top 5 areas by family count
    final sortedAreas = areaDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topAreas = sortedAreas.take(5).toList();

    return {
      'totalFamilies': totalFamilies,
      'accepted': accepted,
      'pending': pending,
      'rejected': rejected,
      'discarded': discarded,
      'totalMembers': totalMembers,
      'recentApplications': recentApplications,
      'areaDistribution': topAreas,
    };
  }

  Future<void> _exportReport() async {
    try {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Generating report...')));

      // Fetch all families for both summary stats and details
      final familiesSnapshot = await FirebaseFirestore.instance
          .collection('families')
          .get();

      final data = _computeStatistics(familiesSnapshot);

      final csvContent = StringBuffer();

      csvContent.writeln('Ration Aid - Family Statistics Report');
      csvContent.writeln('Generated on: ${DateTime.now()}');
      csvContent.writeln('');

      csvContent.writeln('OVERVIEW');
      csvContent.writeln('Metric,Value');
      csvContent.writeln('Total Families,${data['totalFamilies']}');
      csvContent.writeln('Total Members,${data['totalMembers']}');
      csvContent.writeln(
        'Recent Applications (7d),${data['recentApplications']}',
      );
      csvContent.writeln('');

      csvContent.writeln('STATUS BREAKDOWN');
      csvContent.writeln('Status,Count');
      csvContent.writeln('Accepted,${data['accepted']}');
      csvContent.writeln('Pending,${data['pending']}');
      csvContent.writeln('Rejected,${data['rejected']}');
      csvContent.writeln('Discarded,${data['discarded']}');
      csvContent.writeln('');

      csvContent.writeln('TOP AREAS BY FAMILY COUNT');
      csvContent.writeln('Area,Family Count');
      final areaDistribution =
          data['areaDistribution'] as List<MapEntry<String, int>>;
      for (final area in areaDistribution) {
        csvContent.writeln('${area.key},${area.value}');
      }
      csvContent.writeln('');

      // Detailed Family Data Section
      csvContent.writeln('DETAILED FAMILY DATA');
      csvContent.writeln(
        'CNIC,Head Name,Status,Area,Family Size,Monthly Income,Contact,Email,Application Date,Assistance Needs',
      );

      for (final doc in familiesSnapshot.docs) {
        final familyData = doc.data();
        final cnic = familyData['cnic'] ?? 'N/A';
        final headName = familyData['headName'] ?? 'N/A';
        final status = familyData['status'] ?? 'N/A';
        final area = familyData['area'] ?? 'N/A';
        final familySize = familyData['familySize'] ?? 0;
        final monthlyIncome = familyData['monthlyIncome'] ?? 0;
        final contact = familyData['contact'] ?? 'N/A';
        final email = familyData['email'] ?? 'N/A';

        final createdAt = familyData['createdAt'] as Timestamp?;
        final createdAtStr = createdAt != null
            ? createdAt.toDate().toString().split(' ')[0]
            : 'N/A';

        final assistanceNeeds = familyData['assistanceNeeds'] ?? 'N/A';

        // Escape commas in fields for CSV
        csvContent.writeln(
          '"$cnic","$headName",$status,"$area",$familySize,$monthlyIncome,"$contact","$email","$createdAtStr","$assistanceNeeds"',
        );
      }

      final filePath = await FileDownloadHelper.downloadCsvFile(
        filename:
            'Family_Statistics_${DateTime.now().millisecondsSinceEpoch}.csv',
        csvContent: csvContent.toString(),
      );

      await AuditService.logSystemAction(
        action: 'Family Statistics Report exported',
        details:
            'Admin successfully exported family statistics as CSV to $filePath',
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
    return AdminScaffold(
      title: 'Family Statistics',
      actions: [
        IconButton(
          icon: const Icon(Icons.download),
          tooltip: 'Export report',
          onPressed: _exportReport,
        ),
      ],
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('families').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                'No family data available.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            );
          }

          final data = _computeStatistics(snapshot.data!);
          final totalFamilies = data['totalFamilies'] as int;
          final accepted = data['accepted'] as int;
          final pending = data['pending'] as int;
          final rejected = data['rejected'] as int;
          final discarded = data['discarded'] as int;
          final totalMembers = data['totalMembers'] as int;
          final recentApplications = data['recentApplications'] as int;
          final areaDistribution =
              data['areaDistribution'] as List<MapEntry<String, int>>;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Overview cards
                _sectionTitle('Overview'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.family_restroom,
                        title: 'Total families',
                        value: totalFamilies.toString(),
                        subtitle: 'Registered households',
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.people,
                        title: 'Total members',
                        value: totalMembers.toString(),
                        subtitle: 'Across families',
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
                        icon: Icons.schedule,
                        title: 'New (7d)',
                        value: recentApplications.toString(),
                        subtitle: 'Recent applications',
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: SizedBox(),
                    ), // Placeholder for alignment
                  ],
                ),

                const SizedBox(height: 24),

                // Status breakdown
                _sectionTitle('Application status'),
                const SizedBox(height: 12),
                FrostedPanel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _statusRow(
                          'Accepted',
                          accepted,
                          totalFamilies,
                          Colors.green,
                        ),
                        const Divider(height: 16),
                        _statusRow(
                          'Pending',
                          pending,
                          totalFamilies,
                          Colors.orange,
                        ),
                        const Divider(height: 16),
                        _statusRow(
                          'Rejected',
                          rejected,
                          totalFamilies,
                          Colors.red,
                        ),
                        const Divider(height: 16),
                        _statusRow(
                          'Discarded',
                          discarded,
                          totalFamilies,
                          Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Area distribution
                _sectionTitle('Top areas by family count'),
                const SizedBox(height: 12),
                if (areaDistribution.isEmpty)
                  FrostedPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No family data available yet.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  ...areaDistribution.asMap().entries.map((entry) {
                    final index = entry.key;
                    final area = entry.value;
                    return FrostedPanel(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.withValues(alpha: 0.2),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        title: Text(
                          area.key,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        trailing: Text(
                          '${area.value} families',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
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
    return FrostedPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, int count, int total, Color color) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
            backgroundColor: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$count ($percentage%)',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
