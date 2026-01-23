import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
  late Future<Map<String, int>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      _statsFuture = _donationService.getDonorStats(userId);
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      _loadStats();
    });
    await _statsFuture;
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
              _FrostedPanel(
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
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No recent donations',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
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
