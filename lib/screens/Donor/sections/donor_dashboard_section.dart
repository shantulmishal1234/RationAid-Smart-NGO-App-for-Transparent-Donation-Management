import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/screens/Admin/widgets/stat_card.dart';
import 'package:ration_aid/services/donation_service.dart';
import 'package:ration_aid/services/family_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_frosted_panel.dart';

/// Donor Dashboard Section - Industry-Level Overview statistics, active tracking, and quick actions
class DonorDashboardSection extends StatefulWidget {
  const DonorDashboardSection({super.key});

  @override
  State<DonorDashboardSection> createState() => _DonorDashboardSectionState();
}

class _DonorDashboardSectionState extends State<DonorDashboardSection> {
  final DonationService _donationService = DonationService();
  final FamilyService _familyService = FamilyService();

  // Optimized streams
  late final Stream<User?> _userStream;
  Stream<Map<String, dynamic>>? _statsStream;
  Stream<List<Donation>>? _recentDonationsStream;

  Stream<List<Family>>? _urgentFamiliesStream;
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
      _statsStream = _donationService.streamDonorStatsAdvanced(user.uid);
      _recentDonationsStream = _donationService.streamRecentDonationsByDonor(
        user.uid,
        limit: 3,
      );

      // Map the generic family stream into a filtered emergency-only list
      _urgentFamiliesStream = _familyService.streamAcceptedFamilies().map(
        (families) => families.where((f) => f.isEmergency).toList(),
      );
    }
  }

  Future<void> _onRefresh() async {
    // Streams are already live — just trigger rebuild to show latest data
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  // GREETING
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

                  // TOP TIER STATS
                  DonorFrostedPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StreamBuilder<Map<String, dynamic>>(
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
                                  title: 'Total Impact',
                                  value: 'Rs 0',
                                  subtitle: 'Start your journey',
                                  icon: Icons.trending_up,
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
                        final totalAmount = data['totalAmount'] ?? 0.0;

                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 220,
                                child: StatCard(
                                  title: 'Total Impact',
                                  value: 'Rs ${totalAmount.toStringAsFixed(0)}',
                                  subtitle: 'Lifetime Contribution',
                                  icon: Icons.trending_up,
                                  color: AppColors.donorGreen,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 200,
                                child: StatCard(
                                  title: 'Donations Made',
                                  value: total.toString(),
                                  subtitle:
                                      '$active active • $completed completed',
                                  icon: Icons.favorite,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 200,
                                child: StatCard(
                                  title: 'Families Supported',
                                  value: families.toString(),
                                  subtitle: 'Directly impacted',
                                  icon: Icons.family_restroom,
                                  color: AppColors.accentGreen,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                        const SizedBox(height: 16),
                        
                        // ── MAKE A DONATION CTA (INSIDE PANEL) ──────────────
                        GestureDetector(
                          onTap: () =>
                              Navigator.pushNamed(context, '/create-donation'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.donorGreen.withValues(alpha: 0.1)
                                  : AppColors.donorGreen.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.donorGreen.withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                // "+" icon container
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.donorGreen.withValues(
                                      alpha: isDark ? 0.3 : 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: AppColors.donorGreen,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Label
                                Expanded(
                                  child: Text(
                                    'Make a Donation',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.donorGreen,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                // Chevron
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.donorGreen,
                                  size: 24,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // FEATURED CAUSES
                  Text(
                    'Urgent Emergency Needs',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _FeaturedEmergencyCarousel(stream: _urgentFamiliesStream),

                  const SizedBox(height: 22),

                  // RECENT DONATIONS
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

// ----------------------------------------------------------------------------
// COMPONENT WIDGETS
// ----------------------------------------------------------------------------

class _FeaturedEmergencyCarousel extends StatelessWidget {
  final Stream<List<Family>>? stream;
  const _FeaturedEmergencyCarousel({required this.stream});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (stream == null) return const SizedBox.shrink();

    return StreamBuilder<List<Family>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return DonorFrostedPanel(
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: AppColors.donorGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No emergency families currently waiting. Thank you to our donors!',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final emFamilies = snapshot.data!.take(5).toList();

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: emFamilies
                .map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _DashboardEmergencyCard(family: f),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class _DashboardEmergencyCard extends StatelessWidget {
  final Family family;
  const _DashboardEmergencyCard({required this.family});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = family.targetAmount > 0
        ? (family.combinedProgress / family.targetAmount).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/family-detail', arguments: family);
      },
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
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
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'EMERGENCY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${family.area}, ${family.city}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'Family of ${family.numberOfAdults + family.numberOfChildren}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: theme.dividerColor,
                color: Colors.red,
                minHeight: 6,
              ),
            ),
          ],
        ),
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
        color: Theme.of(context).cardColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
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
        return const Color(0xFF009688);
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
