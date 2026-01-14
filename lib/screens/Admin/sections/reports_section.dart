import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/widgets/report_card.dart';
import 'package:ration_aid/screens/Admin/Reports&Analytics/hrm_report_screen.dart';
import 'package:ration_aid/screens/Admin/Reports&Analytics/donations_report_screen.dart';
import 'package:ration_aid/screens/Admin/Reports&Analytics/family_statistics_report_screen.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Reports section showing different report types
class ReportsSection extends StatelessWidget {
  final ValueChanged<AdminSection> onSectionChanged;

  const ReportsSection({super.key, required this.onSectionChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('reports'),
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFF7FAFF), Color(0xFFF3F7FF)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered title + subtitle
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Reports & analytics',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Generate and export comprehensive reports for audits and decision-making.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grid inside card container
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.96),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
                children: [
                  ReportCard(
                    icon: Icons.people,
                    title: 'HRM report',
                    description: 'Staff analytics and activity metrics',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HrmReportScreen(),
                        ),
                      );
                    },
                  ),
                  ReportCard(
                    icon: Icons.volunteer_activism,
                    title: 'Donations report',
                    description: 'Financial contributions overview',
                    color: Colors.green,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DonationsReportScreen(),
                        ),
                      );
                    },
                  ),
                  ReportCard(
                    icon: Icons.family_restroom,
                    title: 'Family statistics',
                    description: 'Household distribution analysis',
                    color: Colors.orange,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FamilyStatisticsReportScreen(),
                        ),
                      );
                    },
                  ),
                  ReportCard(
                    icon: Icons.receipt_long,
                    title: 'Audit logs',
                    description: 'System activity and changes',
                    color: Colors.purple,
                    onTap: () {
                      onSectionChanged(AdminSection.audit);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
