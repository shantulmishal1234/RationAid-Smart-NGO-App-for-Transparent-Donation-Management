import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/widgets/frosted_panel.dart';

class PerformanceSection extends StatefulWidget {
  const PerformanceSection({super.key});

  @override
  State<PerformanceSection> createState() => _PerformanceSectionState();
}

class _PerformanceSectionState extends State<PerformanceSection> {
  // Do NOT capture uid at field-init time — auth may not have resolved yet.
  // Use FirebaseAuth.instance.currentUser inside _load() instead.
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Delay slightly to let auth settle before firing Firestore query
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // Guard: don't query Firestore if auth hasn't resolved
    if (uid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await DeliveryService.getDistributorPerformance(uid);
      if (mounted) setState(() => _stats = stats);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.volunteerBlue,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.volunteerBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.bar_chart,
                    color: AppColors.volunteerBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Performance',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Pull to refresh',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (_loading)
              const Center(
                child: CircularProgressIndicator(
                  color: AppColors.volunteerBlue,
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 64,
                        color: Colors.red.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Could not load performance data',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.volunteerBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_stats == null || (_stats!['total'] as int) == 0)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    Icon(
                      Icons.bar_chart_outlined,
                      size: 72,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No deliveries yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Complete your first delivery to see stats here',
                      style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    ),
                  ],
                ),
              )
            else ...[
              // Completion Rate card (big)
              _BigRateCard(
                isDark: isDark,
                title: 'Completion Rate',
                rate: (_stats!['completionRate'] as double),
                color: AppColors.volunteerBlue,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(height: 14),
              _BigRateCard(
                isDark: isDark,
                title: 'On-Time Rate',
                rate: (_stats!['onTimeRate'] as double),
                color: Colors.green,
                icon: Icons.timer_outlined,
              ),
              const SizedBox(height: 20),

              // Stats grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _statCard(
                    isDark: isDark,
                    label: 'Total Assigned',
                    value: '${_stats!['total']}',
                    icon: Icons.assignment_outlined,
                    color: AppColors.volunteerBlue,
                  ),
                  _statCard(
                    isDark: isDark,
                    label: 'Completed',
                    value: '${_stats!['completed']}',
                    icon: Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  _statCard(
                    isDark: isDark,
                    label: 'Failed',
                    value: '${_stats!['failed']}',
                    icon: Icons.cancel_outlined,
                    color: Colors.red,
                  ),
                  _statCard(
                    isDark: isDark,
                    label: 'In Progress',
                    value: '${_stats!['pending']}',
                    icon: Icons.local_shipping_outlined,
                    color: Colors.orange,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required bool isDark,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return FrostedPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigRateCard extends StatelessWidget {
  final bool isDark;
  final String title;
  final double rate;
  final Color color;
  final IconData icon;

  const _BigRateCard({
    required this.isDark,
    required this.title,
    required this.rate,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (rate / 100).clamp(0.0, 1.0),
                    backgroundColor: color.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '${rate.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
