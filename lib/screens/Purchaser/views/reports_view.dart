import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/widgets/frosted_panel.dart';
import 'package:ration_aid/services/report_pdf_service.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/screens/Purchaser/widgets/charts/spending_trend_chart.dart';
import 'package:ration_aid/screens/Purchaser/widgets/charts/category_pie_chart.dart';
import 'package:ration_aid/screens/Purchaser/widgets/expandable_transaction_card.dart';
import 'package:ration_aid/services/report_csv_service.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({super.key});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  late Stream<List<ProcurementRequest>> _reportsStream;
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    // Fix #24: Scope stream to current purchaser's UID only
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _reportsStream = ProcurementService.streamMyRequests(uid);
  }

  Future<void> _showCustomRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(data: pkTheme(context), child: child!);
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  ThemeData pkTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      colorScheme: ColorScheme.light(
        primary: AppColors.purchaserOrange,
        onPrimary: Colors.white,
        surface: Theme.of(context).cardColor,
        onSurface: Theme.of(context).textTheme.bodyLarge!.color!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM dd, yyyy');

    return StreamBuilder<List<ProcurementRequest>>(
      stream: _reportsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allRequests = snapshot.data ?? [];

        // Fix #23: Include ALL post-verified statuses for accurate spend calculation
        final verifiedRequests = allRequests.where((r) {
          final isCountable =
              r.status == ProcurementStatus.verified ||
              r.status == ProcurementStatus.stocked ||
              r.status == ProcurementStatus.in_transit ||
              r.status == ProcurementStatus.delivered;
          if (!isCountable) return false;
          if (_selectedDateRange != null) {
            // Use verifiedAt if available, else createdAt as fallback
            final dateToCheck = r.verifiedAt ?? r.createdAt;
            return dateToCheck.isAfter(
                  _selectedDateRange!.start.subtract(
                    const Duration(seconds: 1),
                  ),
                ) &&
                dateToCheck.isBefore(
                  _selectedDateRange!.end.add(const Duration(days: 1)),
                );
          }
          return true;
        }).toList();

        // Sort by key date descending
        verifiedRequests.sort(
          (a, b) => (b.verifiedAt ?? DateTime(0)).compareTo(
            a.verifiedAt ?? DateTime(0),
          ),
        );

        // --- 1. Financial KPIs ---
        double totalSpent = 0;
        double totalBudgetLimit = 0;

        for (var req in verifiedRequests) {
          totalSpent += req.totalSpent;
          totalBudgetLimit += req.budgetLimit;
        }

        double budgetUtilization = totalBudgetLimit > 0
            ? (totalSpent / totalBudgetLimit)
            : 0;

        // Pending Value (Global)
        final pendingCost = allRequests
            .where((r) => r.status == ProcurementStatus.purchased)
            .fold(0.0, (sum, r) => sum + r.totalSpent);

        // --- 2. Category Breakdown ---
        final Map<String, double> categorySpend = {};
        for (var req in verifiedRequests) {
          for (var item in req.items) {
            categorySpend[item.name] =
                (categorySpend[item.name] ?? 0) + item.actualCost;
          }
        }

        // --- 3. Spending Trends (Dynamic) ---
        // Logic: If Date Range Selected -> Show trend within that range
        // If NO Date Range -> Show Last 7 Days
        final Map<DateTime, double> dailySpending = {};

        DateTime start =
            _selectedDateRange?.start ??
            DateTime.now().subtract(const Duration(days: 6));
        DateTime end = _selectedDateRange?.end ?? DateTime.now();

        // If range > 30 days, maybe group by week? For now, stick to daily but limited logic
        // Ensuring we initialize the map for the range to show empty days
        int daysCount = end.difference(start).inDays + 1;
        if (daysCount > 14) {
          // If lots of days, just populate from data to avoid 100 empty bars
          // Or ideally, group by week. Let's start with populated from data only if range is huge
        } else {
          for (int i = 0; i < daysCount; i++) {
            final d = start.add(Duration(days: i));
            final normalized = DateTime(d.year, d.month, d.day);
            dailySpending[normalized] = 0.0;
          }
        }

        for (var req in verifiedRequests) {
          if (req.verifiedAt != null) {
            final d = req.verifiedAt!;
            final normalizedDate = DateTime(d.year, d.month, d.day);
            // Only add if it falls in our visual range (which verifiedRequests already is filtered by)
            dailySpending[normalizedDate] =
                (dailySpending[normalizedDate] ?? 0) + req.totalSpent;
          }
        }

        return RefreshIndicator(
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              // Header with Filter
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
                          ? AppColors.purchaserOrange
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
                        DateTime start = now;
                        if (value == 'today') {
                          start = DateTime(now.year, now.month, now.day);
                        } else if (value == '7days') {
                          start = now.subtract(const Duration(days: 6));
                        } else if (value == '30days') {
                          start = now.subtract(const Duration(days: 29));
                        } else if (value == 'month') {
                          start = DateTime(now.year, now.month, 1);
                        }

                        final end = DateTime(
                          now.year,
                          now.month,
                          now.day,
                          23,
                          59,
                          59,
                        );
                        setState(() {
                          _selectedDateRange = DateTimeRange(
                            start: start,
                            end: end,
                          );
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
              if (_selectedDateRange != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Chip(
                        label: Text(
                          '${dateFormat.format(_selectedDateRange!.start)} - ${dateFormat.format(_selectedDateRange!.end)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onDeleted: () =>
                            setState(() => _selectedDateRange = null),
                        backgroundColor: AppColors.purchaserOrange.withValues(
                          alpha: 0.1,
                        ),
                        side: BorderSide(
                          color: AppColors.purchaserOrange.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // KPI Row
              Row(
                children: [
                  Expanded(
                    child: _buildKPICard(
                      theme,
                      'Total Spend',
                      'Rs ${(totalSpent / 1000).toStringAsFixed(1)}K',
                      Icons.account_balance_wallet_outlined,
                      Colors.green[600]!,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildKPICard(
                      theme,
                      'Budget Use',
                      '${(budgetUtilization * 100).toStringAsFixed(0)}%',
                      Icons.pie_chart,
                      budgetUtilization > 1 ? Colors.red : Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildKPICard(
                      theme,
                      'Pending',
                      'Rs ${(pendingCost / 1000).toStringAsFixed(1)}K',
                      Icons.hourglass_empty,
                      Colors.orange,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Spending Trend Chart (Interactive)
              FrostedPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.bar_chart,
                          color: AppColors.purchaserOrange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedDateRange != null
                              ? 'Spending Trend (Selected)'
                              : 'Spending Trend (Last 7 Days)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SpendingTrendChart(dailyData: dailySpending),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Category Breakdown Pie Chart
              FrostedPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.donut_small,
                          color: AppColors.purchaserOrange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Spending by Category',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CategoryPieChart(categoryData: categorySpend),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Transaction Log (Expandable Cards)
              FrostedPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent Transactions',
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
                    if (verifiedRequests.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Text(
                            'No transactions found in this period.',
                            style: TextStyle(color: theme.disabledColor),
                          ),
                        ),
                      ),

                    ...verifiedRequests
                        .take(20)
                        .map((r) => ExpandableTransactionCard(request: r)),

                    if (verifiedRequests.length > 20)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            '+ ${verifiedRequests.length - 20} more records',
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

              const SizedBox(height: 40),

              // Export Section
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: theme.cardColor,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      builder: (context) => SafeArea(
                        child: Wrap(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                "Export Report",
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ListTile(
                              leading: const Icon(
                                Icons.picture_as_pdf,
                                color: Colors.red,
                              ),
                              title: const Text("Export as PDF"),
                              subtitle: const Text(
                                "Best for printing and sharing",
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                ReportPdfService.generateAndOpenReport(
                                  verifiedRequests,
                                  _selectedDateRange,
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(
                                Icons.table_chart,
                                color: Colors.green,
                              ),
                              title: const Text("Export as CSV (Excel)"),
                              subtitle: const Text("Best for data analysis"),
                              onTap: () {
                                Navigator.pop(context);
                                ReportCsvService.generateAndOpenReport(
                                  verifiedRequests,
                                  _selectedDateRange,
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Export Report'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKPICard(
    ThemeData theme,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
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
              color: theme.colorScheme.onSurface,
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

// Helper Widget
class ConstSpacer extends StatelessWidget {
  const ConstSpacer({super.key});
  @override
  Widget build(BuildContext context) => const Spacer();
}
