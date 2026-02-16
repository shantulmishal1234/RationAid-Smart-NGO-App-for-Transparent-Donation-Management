import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/screens/Admin/widgets/stat_card.dart';
import 'package:ration_aid/services/donation_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Donor Dashboard Section - Overview statistics and quick actions
/// Matching Admin Dashboard style with frosted panels
class DonorDashboardSection extends StatefulWidget {
  const DonorDashboardSection({super.key});

  @override
  State<DonorDashboardSection> createState() => _DonorDashboardSectionState();
}

class _DonorDashboardSectionState extends State<DonorDashboardSection> {
  final DonationService _donationService = DonationService();
  late Stream<Donation?> _activeDonationStream;
  late Stream<Map<String, int>> _statsStream;

  @override
  void initState() {
    super.initState();
    _setupStreams();
  }

  void _setupStreams() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _activeDonationStream = _donationService.streamActiveDonation(user.uid);
      _statsStream = _donationService.streamDonorStats(user.uid);
    } else {
      _activeDonationStream = Stream.value(null);
      _statsStream = Stream.value({});
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      _setupStreams();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    final isDark = theme.brightness == Brightness.dark;

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
                          AppColors.donorGreen.withOpacity(0.18),
                          AppColors.accentGreen.withOpacity(0.12),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withOpacity(0.3)
                              : AppColors.donorGreen.withOpacity(0.18),
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
                          'Thank you for making a difference, ${user?.displayName ?? 'Donor'}!',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Active Donation Card (Live Tracking)
              StreamBuilder<Donation?>(
                stream: _activeDonationStream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data == null) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _ActiveDonationCard(donation: snapshot.data!),
                  );
                },
              ),

              _FrostedPanel(
                child: StreamBuilder<Map<String, int>>(
                  stream: _statsStream,
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
                            subtitle: '$active active • $completed completed',
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
              _FrostedPanel(
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
              _FrostedPanel(
                padding: const EdgeInsets.all(12),
                child: StreamBuilder<List<Donation>>(
                  stream: _donationService.streamRecentDonationsByDonor(
                    user!.uid,
                    limit: 3,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
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
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.3,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No donations yet',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Start making a difference today!',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.4),
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
  }
}

class _FrostedPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _FrostedPanel({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(isDark ? 0.6 : 0.82),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.white.withOpacity(0.7),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(14),
        child: child,
      ),
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
        color: Theme.of(context).cardColor.withOpacity(0.6),
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
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
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
          color: theme.cardColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.onSurface.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.15),
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
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
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
      case DonationStatus.inProcess:
        return Colors.blue;
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

class _ActiveDonationCard extends StatelessWidget {
  final Donation donation;

  const _ActiveDonationCard({required this.donation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Determine gradient based on status
    List<Color> gradientColors;
    IconData icon;
    String title;
    String subtitle;

    switch (donation.status) {
      case DonationStatus.outForDelivery:
        gradientColors = [const Color(0xFF00BCD4), const Color(0xFF0097A7)];
        icon = Icons.local_shipping;
        title = 'Out for Delivery';
        subtitle = 'Your donation is on its way!';
        break;
      case DonationStatus.inProcess:
        gradientColors = [Colors.blue, Colors.blue.shade700];
        icon = Icons.inventory;
        title = 'Processing';
        subtitle = 'Being prepared for delivery';
        break;
      case DonationStatus.verified:
        gradientColors = [Colors.green, Colors.green.shade700];
        icon = Icons.verified;
        title = 'Verified';
        subtitle = 'Approved for donation';
        break;
      case DonationStatus.pending:
      case DonationStatus.underVerification:
        gradientColors = [Colors.orange, Colors.orange.shade800];
        icon = Icons.access_time;
        title = 'Under Review';
        subtitle = 'Pending verification';
        break;
      default:
        gradientColors = [Colors.grey, Colors.grey.shade700];
        icon = Icons.info;
        title = 'Status Update';
        subtitle = donation.status.displayName;
    }

    return InkWell(
      onTap: () {
        Navigator.pushNamed(context, '/donation-tracking', arguments: donation);
      },
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background pattern opacity
            Positioned(
              right: -20,
              top: -20,
              child: Icon(
                icon,
                size: 100,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.circle, size: 8, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'LIVE UPDATE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Just now indicator if needed
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(icon, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
