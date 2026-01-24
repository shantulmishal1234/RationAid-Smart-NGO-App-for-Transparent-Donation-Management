import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/utils/admin_helpers.dart';
import 'package:ration_aid/screens/Admin/widgets/stat_card.dart';
import 'package:ration_aid/screens/Admin/widgets/alert_tile.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Dashboard section showing overview statistics and alerts
/// Optimized: Uses StatefulWidget to cache Future and prevent duplicate API calls
class DashboardSection extends StatefulWidget {
  const DashboardSection({super.key});

  @override
  State<DashboardSection> createState() => _DashboardSectionState();
}

class _DashboardSectionState extends State<DashboardSection> {
  // Store future as stable reference to prevent recreation on rebuilds
  late Future<Map<String, int>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats({bool forceRefresh = false}) {
    _statsFuture = AdminHelpers.loadAllDashboardStats(
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _onRefresh() async {
    setState(() {
      _loadStats(forceRefresh: true);
    });
    await _statsFuture;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: Padding(
        key: const ValueKey('dashboard'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryBlue.withOpacity(0.18),
                          AppColors.accentGreen.withOpacity(0.12),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withOpacity(0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.dashboard_rounded,
                      color: AppColors.primaryBlue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Impact overview',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Snapshot of supported families and your frontline team.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Live stats in frosted panel - OPTIMIZED with stable future
              FrostedPanel(
                child: FutureBuilder<Map<String, int>>(
                  future: _statsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Row(
                        children: [
                          Expanded(child: _SkeletonStatCard()),
                          SizedBox(width: 12),
                          Expanded(child: _SkeletonStatCard()),
                        ],
                      );
                    }

                    if (!snapshot.hasData || snapshot.hasError) {
                      return const Row(
                        children: [
                          Expanded(
                            child: StatCard(
                              title: 'Families',
                              value: '-',
                              subtitle: 'No data yet',
                              icon: Icons.family_restroom,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: StatCard(
                              title: 'Volunteers & staff',
                              value: '-',
                              subtitle: 'No data yet',
                              icon: Icons.group,
                              color: AppColors.accentGreen,
                            ),
                          ),
                        ],
                      );
                    }

                    final data = snapshot.data!;
                    final famTotal = data['fam_total']!;
                    final famAccepted = data['fam_accepted']!;
                    final famPending = data['fam_pending']!;
                    final memTotal = data['mem_total']!;
                    final memAdmins = data['mem_admins']!;
                    final memVolunteers = data['mem_volunteers']!;

                    return Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            title: 'Families',
                            value: famTotal.toString(),
                            subtitle:
                                '$famAccepted supported • $famPending pending',
                            icon: Icons.family_restroom,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            title: 'Volunteers & staff',
                            value: memTotal.toString(),
                            subtitle:
                                '$memAdmins admins • $memVolunteers volunteers',
                            icon: Icons.group,
                            color: AppColors.accentGreen,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Secondary stats (kept as-is, but text not about verification bar)
              FrostedPanel(
                child: const Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        title: 'Donations',
                        value: '92',
                        subtitle: '12 to review today',
                        icon: Icons.volunteer_activism,
                        color: Color(0xFFFFA726),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        title: 'Deliveries',
                        value: '58',
                        subtitle: '9 scheduled for today',
                        icon: Icons.local_shipping,
                        color: Color(0xFF7E57C2),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // Alerts header
              Row(
                children: [
                  Text(
                    'Today’s alerts',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Action needed',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Static alerts
              FrostedPanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: const Column(
                  children: [
                    AlertTile(
                      icon: Icons.warning_amber_rounded,
                      text:
                          'Heatwave alert: Prioritize water distribution in Barkat Market and Shahdara.',
                      color: Color(0xFFEF5350),
                    ),
                    Divider(height: 1),
                    AlertTile(
                      icon: Icons.inventory_2_rounded,
                      text:
                          'Stock check required for flour and cooking oil in Johar Town warehouse.',
                      color: AppColors.primaryBlue,
                    ),
                    Divider(height: 1),
                    AlertTile(
                      icon: Icons.bug_report,
                      text:
                          'One system error logged in audit trail. Review the HRM report for details.',
                      color: Color(0xFFFFA726),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Static tasks
              Text(
                'Today’s tasks',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              FrostedPanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: const Column(
                  children: [
                    AlertTile(
                      icon: Icons.checklist_rounded,
                      text:
                          'Review at least 10 pending family applications before 6 PM.',
                      color: AppColors.accentGreen,
                    ),
                    Divider(height: 1),
                    AlertTile(
                      icon: Icons.verified,
                      text:
                          'Verify today’s high‑value donations and update donors via SMS or email.',
                      color: Color(0xFF7E57C2),
                    ),
                    Divider(height: 1),
                    AlertTile(
                      icon: Icons.group,
                      text:
                          'Confirm tomorrow’s volunteer rosters for Model Town and Gulberg routes.',
                      color: AppColors.primaryBlue,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton card while loading
class _SkeletonStatCard extends StatelessWidget {
  const _SkeletonStatCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(isDark ? 0.3 : 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
    );
  }
}
