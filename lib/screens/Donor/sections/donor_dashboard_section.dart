import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/screens/Admin/widgets/stat_card.dart';
import 'package:ration_aid/services/donation_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_frosted_panel.dart';

/// Donor Dashboard Section - Overview statistics and quick actions
/// Matching Admin Dashboard style with frosted panels
class DonorDashboardSection extends StatefulWidget {
  const DonorDashboardSection({super.key});

  @override
  State<DonorDashboardSection> createState() => _DonorDashboardSectionState();
}

class _DonorDashboardSectionState extends State<DonorDashboardSection> {
  final DonationService _donationService = DonationService();

  // Optimized streams
  late final Stream<User?> _userStream;
  Stream<Map<String, int>>? _statsStream;
  Stream<List<Donation>>? _recentDonationsStream;
  String? _cachedUid;

  @override
  void initState() {
    super.initState();
    _userStream = FirebaseAuth.instance.userChanges();
    _initUserStreams();
  }

  void _initUserStreams() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.uid != _cachedUid) {
      _cachedUid = user.uid;
      _statsStream = _donationService.streamDonorStats(user.uid);
      _recentDonationsStream = _donationService.streamRecentDonationsByDonor(
        user.uid,
        limit: 3,
      );
    }
  }

  Future<void> _onRefresh() async {
    _initUserStreams(); // Refresh streams on pull-to-refresh
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser?.uid != _cachedUid) {
      _initUserStreams();
    }

    // Listen to user changes for real-time profile updates
    return StreamBuilder<User?>(
      stream: _userStream,
      builder: (context, userSnapshot) {
        final user = userSnapshot.data;

        if (!userSnapshot.hasData || user == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: _onRefresh,
          child: Padding(
            key: const ValueKey('donor-dashboard'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.donorGreen.withValues(alpha: 0.18),
                              AppColors.accentGreen.withValues(alpha: 0.12),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.3)
                                  : AppColors.donorGreen.withValues(
                                      alpha: 0.18,
                                    ),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.volunteer_activism,
                          color: AppColors.donorGreen,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Impact',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Thank you for making a difference, ${user.displayName ?? 'Donor'}!',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  DonorFrostedPanel(
                    child: StreamBuilder<Map<String, int>>(
                      stream: _statsStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
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
                                  title: 'Donations',
                                  value: '0',
                                  subtitle: 'Start your journey',
                                  icon: Icons.volunteer_activism,
                                  color: AppColors.donorGreen,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: StatCard(
                                  title: 'Families',
                                  value: '0',
                                  subtitle: 'No families yet',
                                  icon: Icons.family_restroom,
                                  color: AppColors.accentGreen,
                                ),
                              ),
                            ],
                          );
                        }

                        final data = snapshot.data!;
                        final total = data['total'] ?? 0;
                        final families = data['families'] ?? 0;
                        final active = data['active'] ?? 0;
                        final completed = data['completed'] ?? 0;

                        return Row(
                          children: [
                            Expanded(
                              child: StatCard(
                                title: 'Total Donations',
                                value: total.toString(),
                                subtitle:
                                    '$active active • $completed completed',
                                icon: Icons.volunteer_activism,
                                color: AppColors.donorGreen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: StatCard(
                                title: 'Families Supported',
                                value: families.toString(),
                                subtitle: 'Making an impact',
                                icon: Icons.family_restroom,
                                color: AppColors.accentGreen,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  DonorFrostedPanel(
                    child: _QuickActionButton(
                      icon: Icons.add_circle,
                      label: 'Make a Donation',
                      color: AppColors.donorGreen,
                      onTap: () {
                        // Navigate to create donation
                        Navigator.pushNamed(context, '/create-donation');
                      },
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Recent Donations',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DonorFrostedPanel(
                    padding: const EdgeInsets.all(12),
                    child: StreamBuilder<List<Donation>>(
                      stream: _recentDonationsStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }

                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(20),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.volunteer_activism_outlined,
                                    size: 48,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.3),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No donations yet',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Start making a difference today!',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.4),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: snapshot.data!
                              .map(
                                (donation) => _RecentDonationTile(
                                  donation: donation,
                                  onTap: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/donation-tracking',
                                      arguments: donation,
                                    );
                                  },
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonStatCard extends StatelessWidget {
  const _SkeletonStatCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.6),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.1),
              color.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

class _RecentDonationTile extends StatelessWidget {
  final Donation donation;
  final VoidCallback onTap;

  const _RecentDonationTile({required this.donation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(donation.status);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                donation.donationType == DonationType.cash
                    ? Icons.payments
                    : Icons.inventory_2,
                color: statusColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    donation.donationType == DonationType.cash
                        ? 'Cash • ${donation.familyId == 'general_relief_fund' ? 'General Relief' : 'Family Support'}'
                        : 'In-Kind • ${donation.familyId == 'general_relief_fund' ? 'General Relief' : 'Family Support'}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    donation.status.displayName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Amount or items count
            if (donation.donationType == DonationType.cash)
              Text(
                'Rs ${donation.amount?.toStringAsFixed(0) ?? '0'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.donorGreen,
                ),
              )
            else
              Text(
                '${donation.items?.length ?? 0} items',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(DonationStatus status) {
    switch (status) {
      case DonationStatus.draft:
        return Colors.grey;
      case DonationStatus.pending:
      case DonationStatus.underVerification:
        return Colors.orange;
      case DonationStatus.verified:
      case DonationStatus.pendingAssignment:
      case DonationStatus.inProcess:
        return Colors.blue;
      case DonationStatus.stocked:
        return const Color(0xFF009688); // Teal — In Warehouse
      case DonationStatus.outForDelivery:
        return Colors.purple;
      case DonationStatus.delivered:
      case DonationStatus.closed:
        return Colors.green;
      case DonationStatus.rejected:
        return Colors.red;
    }
  }
}
