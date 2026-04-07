import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/widgets/frosted_panel.dart';
import 'package:intl/intl.dart';

/// Delivery reports & analytics — available only to supervisor distributors.
class DistributorReportsView extends StatefulWidget {
  const DistributorReportsView({super.key});

  @override
  State<DistributorReportsView> createState() => _DistributorReportsViewState();
}

class _DistributorReportsViewState extends State<DistributorReportsView> {
  DateTimeRange? _selectedDateRange;

  Future<void> _showCustomRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.volunteerBlue,
              onPrimary: Colors.white,
              surface: Theme.of(context).cardColor,
              onSurface: Theme.of(context).textTheme.bodyLarge!.color!,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final dateFormat = DateFormat('MMM dd, yyyy');

    if (uid == null) {
      return const Center(child: Text('Please log in'));
    }

    return StreamBuilder<List<DeliveryAssignment>>(
      stream: DeliveryService.getSmartDeliveryStream(uid, true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.volunteerBlue),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading data',
              style: TextStyle(color: Colors.red[400]),
            ),
          );
        }

        final allDeliveries = snapshot.data ?? [];

        // ── Apply date filter ──
        var filtered = allDeliveries;
        if (_selectedDateRange != null) {
          filtered = filtered.where((a) {
            final d = a.deliveredAt ?? a.failedAt ?? a.createdAt;
            return d.isAfter(
                  _selectedDateRange!.start.subtract(
                    const Duration(seconds: 1),
                  ),
                ) &&
                d.isBefore(
                  _selectedDateRange!.end.add(const Duration(days: 1)),
                );
          }).toList();
        }

        // ── KPI Calculations ──
        final total = filtered.length;
        final completed = filtered.where((a) => a.isCompleted).length;
        final failed = filtered.where((a) => a.isFailed).length;
        final active = filtered.where((a) => a.isActive).length;
        final successRate = total > 0 ? (completed / total * 100) : 0.0;
        final familiesServed = filtered
            .where((a) => a.isCompleted)
            .fold<int>(0, (sum, a) => sum + a.familySize);

        // ── Delivery Timeline Trend ──
        final Map<DateTime, int> dailyCompleted = {};
        final start =
            _selectedDateRange?.start ??
            DateTime.now().subtract(const Duration(days: 6));
        final end = _selectedDateRange?.end ?? DateTime.now();
        final dayCount = end.difference(start).inDays + 1;

        for (int i = 0; i < dayCount; i++) {
          final d = start.add(Duration(days: i));
          dailyCompleted[DateTime(d.year, d.month, d.day)] = 0;
        }

        for (var a in filtered.where((a) => a.isCompleted)) {
          final d = a.deliveredAt ?? a.createdAt;
          final key = DateTime(d.year, d.month, d.day);
          dailyCompleted[key] = (dailyCompleted[key] ?? 0) + 1;
        }

        // ── Status Distribution ──
        final statusCounts = <String, int>{
          'Completed': completed,
          'Active': active,
          'Failed': failed,
        };

        // Sort filtered by date desc
        final sortedDeliveries = List<DeliveryAssignment>.from(filtered)
          ..sort((a, b) {
            final da = a.deliveredAt ?? a.failedAt ?? a.createdAt;
            final db = b.deliveredAt ?? b.failedAt ?? b.createdAt;
            return db.compareTo(da);
          });

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ── Header ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Reports & Analytics',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 0.5,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.calendar_month_outlined,
                    color: _selectedDateRange != null
                        ? AppColors.volunteerBlue
                        : theme.hintColor,
                  ),
                  tooltip: 'Filter Date Range',
                  onSelected: (value) async {
                    if (value == 'clear') {
                      setState(() => _selectedDateRange = null);
                    } else if (value == 'custom') {
                      _showCustomRangePicker();
                    } else {
                      final now = DateTime.now();
                      DateTime s = now;
                      if (value == 'today') {
                        s = DateTime(now.year, now.month, now.day);
                      } else if (value == '7days') {
                        s = now.subtract(const Duration(days: 6));
                      } else if (value == '30days') {
                        s = now.subtract(const Duration(days: 29));
                      } else if (value == 'month') {
                        s = DateTime(now.year, now.month, 1);
                      }
                      final e = DateTime(
                        now.year,
                        now.month,
                        now.day,
                        23,
                        59,
                        59,
                      );
                      setState(() {
                        _selectedDateRange = DateTimeRange(start: s, end: e);
                      });
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'today', child: Text('Today')),
                    const PopupMenuItem(
                      value: '7days',
                      child: Text('Last 7 Days'),
                    ),
                    const PopupMenuItem(
                      value: '30days',
                      child: Text('Last 30 Days'),
                    ),
                    const PopupMenuItem(
                      value: 'month',
                      child: Text('This Month'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'custom',
                      child: Text('Custom Range...'),
                    ),
                    if (_selectedDateRange != null)
                      const PopupMenuItem(
                        value: 'clear',
                        child: Text(
                          'Clear Filter',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Active date chip
            if (_selectedDateRange != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Chip(
                      label: Text(
                        '${dateFormat.format(_selectedDateRange!.start)} – ${dateFormat.format(_selectedDateRange!.end)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onDeleted: () =>
                          setState(() => _selectedDateRange = null),
                      backgroundColor: AppColors.volunteerBlue.withValues(
                        alpha: 0.1,
                      ),
                      side: BorderSide(
                        color: AppColors.volunteerBlue.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // ── KPI Cards ──
            Row(
              children: [
                Expanded(
                  child: _KPICard(
                    title: 'Completed',
                    value: '$completed',
                    icon: Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KPICard(
                    title: 'Success Rate',
                    value: '${successRate.toStringAsFixed(0)}%',
                    icon: Icons.trending_up,
                    color: AppColors.volunteerBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KPICard(
                    title: 'People Fed',
                    value: '$familiesServed',
                    icon: Icons.people_outline,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _KPICard(
                    title: 'Total',
                    value: '$total',
                    icon: Icons.local_shipping_outlined,
                    color: AppColors.volunteerBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KPICard(
                    title: 'Active',
                    value: '$active',
                    icon: Icons.pending_actions,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KPICard(
                    title: 'Failed',
                    value: '$failed',
                    icon: Icons.cancel_outlined,
                    color: Colors.red,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Delivery Trend ──
            FrostedPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.bar_chart,
                        color: AppColors.volunteerBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _selectedDateRange != null
                            ? 'Delivery Trend (Selected)'
                            : 'Delivery Trend (Last 7 Days)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SimpleTrendBars(data: dailyCompleted),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Status Distribution ──
            FrostedPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.donut_small,
                        color: AppColors.volunteerBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Status Distribution',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...statusCounts.entries.map((e) {
                    final pct = total > 0 ? (e.value / total * 100) : 0.0;
                    final color = e.key == 'Completed'
                        ? Colors.green
                        : e.key == 'Active'
                        ? Colors.blue
                        : Colors.red;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(
                              e.key,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (pct / 100).clamp(0.0, 1.0),
                                backgroundColor: color.withValues(alpha: 0.1),
                                valueColor: AlwaysStoppedAnimation(color),
                                minHeight: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '${e.value}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Recent Delivery Log ──
            FrostedPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Deliveries',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Icon(
                        Icons.receipt_long,
                        color: theme.hintColor,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (sortedDeliveries.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'No deliveries found in this period.',
                          style: TextStyle(color: theme.disabledColor),
                        ),
                      ),
                    ),
                  ...sortedDeliveries
                      .take(20)
                      .map((a) => _DeliveryLogCard(assignment: a)),
                  if (sortedDeliveries.length > 20)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '+ ${sortedDeliveries.length - 20} more records',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── KPI Card ────────────────────────────────────────────────────────────

class _KPICard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KPICard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Simple Trend Bars ───────────────────────────────────────────────────

class _SimpleTrendBars extends StatelessWidget {
  final Map<DateTime, int> data;
  const _SimpleTrendBars({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
        child: Text(
          'No data to display',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    final sorted = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxVal = sorted.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final effectiveMax = maxVal > 0 ? maxVal : 1;

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: sorted.map((entry) {
          final barHeight = (entry.value / effectiveMax * 90).clamp(4.0, 90.0);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${entry.value}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.volunteerBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: AppColors.volunteerBlue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d').format(entry.key),
                    style: TextStyle(
                      fontSize: 9,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Delivery Log Card ───────────────────────────────────────────────────

class _DeliveryLogCard extends StatelessWidget {
  final DeliveryAssignment assignment;
  const _DeliveryLogCard({required this.assignment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = assignment;
    final dateStr = a.deliveredAt != null
        ? DateFormat('MMM dd, hh:mm a').format(a.deliveredAt!)
        : DateFormat('MMM dd, hh:mm a').format(a.createdAt);

    final statusColor = a.isCompleted
        ? Colors.green
        : a.isFailed
        ? Colors.red
        : Colors.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${a.familyArea}, ${a.familyCity}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${a.assignedPackName ?? "Pack"} · ${a.items.length} items · Family of ${a.familySize}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  a.status.displayName,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
