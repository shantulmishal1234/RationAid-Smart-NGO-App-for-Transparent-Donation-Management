import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/utils/file_download_helper.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';

class HrmReportScreen extends StatefulWidget {
  const HrmReportScreen({super.key});

  @override
  State<HrmReportScreen> createState() => _HrmReportScreenState();
}

class _HrmReportScreenState extends State<HrmReportScreen> {
  @override
  void initState() {
    super.initState();
    _logReportView();
  }

  Future<void> _logReportView() async {
    await AuditService.logSystemAction(
      action: 'HRM Report viewed',
      details: 'Admin accessed HRM analytics and staff report',
    );
  }

  Map<String, dynamic> _computeSummary(QuerySnapshot allUsersSnap) {
    int totalMembers = allUsersSnap.docs.length;
    int purchasers = 0;
    int distributors = 0;

    // Activity tracking
    final now = DateTime.now();
    final cutoff30 = now.subtract(const Duration(days: 30));
    final cutoff7 = now.subtract(const Duration(days: 7));

    int inactiveCount = 0;
    int activeLastWeek = 0;
    int activeLastMonth = 0;
    int neverLoggedIn = 0;
    int recentlyJoined = 0;

    for (final doc in allUsersSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;

      // Role counts
      final roles = List<String>.from(data['roles'] ?? []);
      if (roles.contains('purchaser')) purchasers++;
      if (roles.contains('distributor')) distributors++;

      // Activity counts
      final lastLoginTs = data['lastLoginAt'] as Timestamp?;
      if (lastLoginTs == null) {
        neverLoggedIn++;
        inactiveCount++;
      } else {
        final lastLogin = lastLoginTs.toDate();
        if (lastLogin.isAfter(cutoff7)) {
          activeLastWeek++;
        }
        if (lastLogin.isAfter(cutoff30)) {
          activeLastMonth++;
        } else {
          inactiveCount++;
        }
      }

      // Join counts
      final joiningTs = data['joiningDate'] as Timestamp?;
      if (joiningTs != null) {
        final joiningDate = joiningTs.toDate();
        if (joiningDate.isAfter(cutoff30)) {
          recentlyJoined++;
        }
      }
    }

    return {
      'totalMembers': totalMembers,
      'purchasers': purchasers,
      'distributors': distributors,
      'inactiveCount': inactiveCount,
      'activeLastWeek': activeLastWeek,
      'activeLastMonth': activeLastMonth,
      'neverLoggedIn': neverLoggedIn,
      'recentlyJoined': recentlyJoined,
    };
  }

  Future<void> _exportReport() async {
    try {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Generating report...')));

      // Fetch all users (purchasers, distributors, and donors) for the report data
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

      final data = _computeSummary(usersSnapshot);

      final csvContent = StringBuffer();

      // Header
      csvContent.writeln('Ration Aid - HRM Report');
      csvContent.writeln('Generated on: ${DateTime.now()}');
      csvContent.writeln('');

      // Overview Section
      csvContent.writeln('OVERVIEW');
      csvContent.writeln('Metric,Value');
      csvContent.writeln('Total Staff,${data['totalMembers']}');
      csvContent.writeln('Purchasers,${data['purchasers']}');
      csvContent.writeln('Distributors,${data['distributors']}');
      csvContent.writeln('Recently Joined (30d),${data['recentlyJoined']}');
      csvContent.writeln('');

      // Activity Section
      csvContent.writeln('ACTIVITY & ENGAGEMENT');
      csvContent.writeln('Status,Count');
      csvContent.writeln('Active (Last 7 days),${data['activeLastWeek']}');
      csvContent.writeln('Active (Last 30 days),${data['activeLastMonth']}');
      csvContent.writeln('Inactive (30+ days),${data['inactiveCount']}');
      csvContent.writeln('Never logged in,${data['neverLoggedIn']}');
      csvContent.writeln('');

      // Detailed Member Data Section
      csvContent.writeln('DETAILED MEMBER DATA');
      csvContent.writeln(
        'Name,Email,Roles,Department,Assigned Area,Joining Date,Last Login,Delivery Count,Status',
      );

      // Using the same snapshot minus admin users where possible
      final filteredDocs = usersSnapshot.docs.where((doc) {
        final r = List<String>.from((doc.data() as Map)['roles'] ?? []);
        return r.contains('purchaser') ||
            r.contains('distributor') ||
            r.contains('donor');
      }).toList();

      for (final doc in filteredDocs) {
        final userData = doc.data();
        final name = userData['name'] ?? 'N/A';
        final email = userData['email'] ?? 'N/A';
        final roles = List<String>.from(userData['roles'] ?? []).join('; ');
        final department = userData['department'] ?? 'N/A';
        final assignedArea = userData['assignedArea'] ?? 'N/A';

        final joiningDate = userData['joiningDate'] as Timestamp?;
        final joiningDateStr = joiningDate != null
            ? joiningDate.toDate().toString().split(' ')[0]
            : 'N/A';

        final lastLogin = userData['lastLoginAt'] as Timestamp?;
        final lastLoginStr = lastLogin != null
            ? lastLogin.toDate().toString().split('.')[0]
            : 'Never';

        final deliveryCount = userData['deliveryCount'] ?? 0;

        // Determine status based on last login
        String status;
        if (lastLogin == null) {
          status = 'Never Logged In';
        } else {
          final daysSinceLogin = DateTime.now()
              .difference(lastLogin.toDate())
              .inDays;
          if (daysSinceLogin <= 7) {
            status = 'Active';
          } else if (daysSinceLogin <= 30) {
            status = 'Recently Active';
          } else {
            status = 'Inactive';
          }
        }

        // Escape commas in fields for CSV
        csvContent.writeln(
          '"$name","$email","$roles","$department","$assignedArea",$joiningDateStr,$lastLoginStr,$deliveryCount,$status',
        );
      }

      final filePath = await FileDownloadHelper.downloadCsvFile(
        filename: 'HRM_Report_${DateTime.now().millisecondsSinceEpoch}.csv',
        csvContent: csvContent.toString(),
      );

      await AuditService.logSystemAction(
        action: 'HRM Report exported',
        details: 'Admin successfully exported HRM report as CSV to $filePath',
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
      title: 'HRM Report',
      actions: [
        IconButton(
          icon: const Icon(Icons.download),
          tooltip: 'Export report',
          onPressed: _exportReport,
        ),
      ],
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                'No HR data available.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            );
          }

          final data = _computeSummary(snapshot.data!);
          final totalMembers = data['totalMembers'] as int;
          final purchasers = data['purchasers'] as int;
          final distributors = data['distributors'] as int;
          final inactiveCount = data['inactiveCount'] as int;
          final activeLastWeek = data['activeLastWeek'] as int;
          final activeLastMonth = data['activeLastMonth'] as int;
          final neverLoggedIn = data['neverLoggedIn'] as int;
          final recentlyJoined = data['recentlyJoined'] as int;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Overview section
                _sectionTitle('Overview'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.groups,
                        title: 'Total staff',
                        value: totalMembers.toString(),
                        subtitle: 'All active accounts',
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.warehouse,
                        title: 'Purchasers',
                        value: purchasers.toString(),
                        subtitle: 'Warehouse team',
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.local_shipping,
                        title: 'Distributors',
                        value: distributors.toString(),
                        subtitle: 'Delivery team',
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryCard(
                        icon: Icons.person_add,
                        title: 'New (30d)',
                        value: recentlyJoined.toString(),
                        subtitle: 'Recently joined staff',
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Activity & engagement
                _sectionTitle('Activity & engagement'),
                const SizedBox(height: 12),
                FrostedPanel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _activityRow(
                          'Active (Last 7 days)',
                          activeLastWeek,
                          Colors.green,
                        ),
                        const Divider(height: 16),
                        _activityRow(
                          'Active (Last 30 days)',
                          activeLastMonth,
                          Colors.blue,
                        ),
                        const Divider(height: 16),
                        _activityRow(
                          'Inactive (30+ days)',
                          inactiveCount,
                          Colors.orange,
                        ),
                        const Divider(height: 16),
                        _activityRow(
                          'Never logged in',
                          neverLoggedIn,
                          Colors.red,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Audit notes
                FrostedPanel(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Audit notes',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This report provides an overview of staff distribution and engagement. '
                        'Use these insights to:\n'
                        '• Evaluate staffing adequacy across roles\n'
                        '• Monitor engagement and attendance trends\n'
                        '• Identify inactive or dormant accounts\n'
                        '• Plan recruitment, training, and restructuring',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
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

  Widget _activityRow(String label, int count, Color color) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
          ),
        ),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
