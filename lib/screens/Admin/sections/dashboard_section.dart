import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/utils/admin_helpers.dart';
import 'package:ration_aid/screens/Admin/widgets/stat_card.dart';
import 'package:ration_aid/screens/Admin/widgets/alert_tile.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_demographics_chart.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_funding_progress_bar.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Dashboard section showing overview statistics and alerts
/// Optimized: Uses StatefulWidget to cache Future and prevent duplicate API calls
class DashboardSection extends StatefulWidget {
  final void Function(AdminSection)? onSectionChanged;

  const DashboardSection({super.key, this.onSectionChanged});

  @override
  State<DashboardSection> createState() => _DashboardSectionState();
}

class _DashboardSectionState extends State<DashboardSection> {
  // Store future as stable reference to prevent recreation on rebuilds
  late Future<Map<String, int>> _statsFuture;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadStats();
    // Auto-refresh stats every 60 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        setState(() {
          _loadStats(forceRefresh: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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
                          AppColors.primaryBlue.withValues(alpha: 0.18),
                          AppColors.accentGreen.withValues(alpha: 0.12),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.18),
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
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
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
                    final memTotalStaff = data['mem_total_staff'] ?? 0;
                    final memDistributors = data['mem_distributors'] ?? 0;
                    final memPurchasers = data['mem_purchasers'] ?? 0;

                    return Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => widget.onSectionChanged?.call(
                              AdminSection.households,
                            ),
                            child: StatCard(
                              title: 'Families',
                              value: famTotal.toString(),
                              subtitle:
                                  '$famAccepted supported • $famPending pending',
                              icon: Icons.family_restroom,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                widget.onSectionChanged?.call(AdminSection.hrm),
                            child: StatCard(
                              title: 'Team Members',
                              value: memTotalStaff.toString(),
                              subtitle:
                                  '$memDistributors distributors • $memPurchasers purchasers',
                              icon: Icons.group,
                              color: AppColors.accentGreen,
                            ),
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
                child: FutureBuilder<Map<String, int>>(
                  future: _statsFuture,
                  builder: (context, snapshot) {
                    final data = snapshot.data ?? {};
                    return Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => widget.onSectionChanged?.call(
                              AdminSection.donations,
                            ),
                            child: StatCard(
                              title: 'Donations',
                              value: (data['donations_total'] ?? 0).toString(),
                              subtitle:
                                  '${data['donations_to_review'] ?? 0} to review',
                              icon: Icons.volunteer_activism,
                              color: const Color(0xFFFFA726),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => widget.onSectionChanged?.call(
                              AdminSection.inventoryIssues,
                            ),
                            child: StatCard(
                              title: 'Stock Available',
                              value: (data['stock_available'] ?? 0).toString(),
                              subtitle: 'Verified packs in inventory',
                              icon: Icons.inventory_2,
                              color: const Color(0xFF7E57C2),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Quick Actions Row
              _buildQuickActionsRow(context, theme),

              const SizedBox(height: 16),

              // Funding Progress Bar
              const AdminFundingProgressBar(),

              const SizedBox(height: 16),

              // Visual Demographics Chart
              FutureBuilder<Map<String, int>>(
                future: _statsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final data = snapshot.data!;
                  return AdminDemographicsChart(
                    accepted: data['fam_accepted'] ?? 0,
                    pending: data['fam_pending'] ?? 0,
                    rejected: data['fam_rejected'] ?? 0,
                    discarded: data['fam_discarded'] ?? 0,
                  );
                },
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
                      color: cs.primaryContainer.withValues(alpha: 0.7),
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

              // Live alerts
              _buildLiveAlerts(theme),

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
              // Live tasks
              _buildLiveTasks(theme),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsRow(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _QuickActionButton(
            icon: Icons.person_add_rounded,
            label: 'Add Member',
            color: AppColors.primaryBlue,
            onTap: () => widget.onSectionChanged?.call(AdminSection.hrm),
          ),
          const SizedBox(width: 12),
          _QuickActionButton(
            icon: Icons.receipt_long_rounded,
            label: 'Verify Purchases',
            color: const Color(0xFFFFA726),
            onTap: () =>
                widget.onSectionChanged?.call(AdminSection.purchaseApproval),
          ),
          const SizedBox(width: 12),
          _QuickActionButton(
            icon: Icons.history_rounded,
            label: 'Audit Trail',
            color: const Color(0xFF7E57C2),
            onTap: () => widget.onSectionChanged?.call(AdminSection.audit),
          ),
          const SizedBox(width: 12),
          _QuickActionButton(
            icon: Icons.bar_chart_rounded,
            label: 'Reports',
            color: AppColors.accentGreen,
            onTap: () => widget.onSectionChanged?.call(AdminSection.reports),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveAlerts(ThemeData theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('procurement_requests')
          .where('status', isEqualTo: 'issue_reported')
          .orderBy('createdAt', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          debugPrint('Live Alerts Error: ${snapshot.error}');
          return FrostedPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: AlertTile(
              icon: Icons.error_outline,
              text: 'Error: ${snapshot.error}',
              color: const Color(0xFFEF5350),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const FrostedPanel(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: AlertTile(
              icon: Icons.check_circle_outline,
              text: 'No active procurement issues at the moment.',
              color: AppColors.accentGreen,
            ),
          );
        }

        return FrostedPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final pack = data['packName'] ?? 'Unknown Pack';
              final area = data['familyAddress'] ?? '';
              return Column(
                children: [
                  AlertTile(
                    icon: Icons.warning_amber_rounded,
                    text: 'Issue reported for $pack delivery in $area.',
                    color: const Color(0xFFEF5350),
                  ),
                  if (doc.id != docs.last.id) const Divider(height: 1),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildLiveTasks(ThemeData theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('donations')
          .where('status', whereIn: ['pending', 'under_verification'])
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return FrostedPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: AlertTile(
              icon: Icons.error_outline,
              text: 'Could not load tasks. Pull to refresh.',
              color: const Color(0xFFEF5350),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const FrostedPanel(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: AlertTile(
              icon: Icons.check_circle_outline,
              text: 'All donations are verified and up to date.',
              color: AppColors.accentGreen,
            ),
          );
        }

        return FrostedPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final donor = data['donorName'] ?? 'Unknown';
              final amountStr = data['donationType'] == 'in_kind'
                  ? 'In-kind items'
                  : 'Rs ${(data['amount'] ?? 0).toStringAsFixed(0)}';
              return Column(
                children: [
                  AlertTile(
                    icon: Icons.pending_actions,
                    text: 'Verify donation from $donor: $amountStr.',
                    color: const Color(0xFFFFA726),
                  ),
                  if (doc.id != docs.last.id) const Divider(height: 1),
                ],
              );
            }).toList(),
          ),
        );
      },
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
        color: theme.cardColor.withValues(alpha: isDark ? 0.3 : 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 100,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
