import 'package:flutter/material.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Purchaser/models/purchaser_enums.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PurchaserHomeView extends StatefulWidget {
  final bool isSupervisor;
  final ValueChanged<PurchaserSection> onSectionChange;

  const PurchaserHomeView({
    super.key,
    required this.isSupervisor,
    required this.onSectionChange,
  });

  @override
  State<PurchaserHomeView> createState() => _PurchaserHomeViewState();
}

class _PurchaserHomeViewState extends State<PurchaserHomeView> {
  Stream<List<ProcurementRequest>>? _statsStream;
  Stream<QuerySnapshot>? _notificationsStream;
  String? _cachedUid;

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  void _initStreams() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.uid != _cachedUid) {
      _cachedUid = user.uid;
      _statsStream = ProcurementService.getSmartHomeStatsStream(
        user.uid,
        widget.isSupervisor,
      );
      _notificationsStream = NotificationService.streamPurchaserNotifications(
        user.uid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Please log in'));
    }

    if (user.uid != _cachedUid) {
      _initStreams();
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back,',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        user.displayName?.split(' ').first ?? 'Purchaser',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (widget.isSupervisor) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.workspace_premium,
                            size: 16,
                            color: Colors.amber,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.purchaserOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.dashboard_rounded,
                  color: AppColors.purchaserOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 1. Main Stats & Financial Overview
          StreamBuilder<List<ProcurementRequest>>(
            stream: _statsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red[400],
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Could not load stats',
                        style: TextStyle(color: Colors.red[400]),
                      ),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: LinearProgressIndicator());
              }
              final requests = snapshot.data!;
              return _buildStatsandFinance(context, requests, theme);
            },
          ),

          const SizedBox(height: 24),

          // 2. Recent Activity Feed
          Text(
            'Recent Activity',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: _notificationsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (snapshot.hasError) {
                return FrostedPanel(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Could not load activity',
                      style: TextStyle(color: Colors.red[400]),
                    ),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return FrostedPanel(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 40,
                          color: theme.disabledColor,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No recent activity',
                          style: TextStyle(color: theme.disabledColor),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final docs = snapshot.data!.docs.take(5).toList();

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildActivityItem(context, data, theme);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatsandFinance(
    BuildContext context,
    List<ProcurementRequest> requests,
    ThemeData theme,
  ) {
    // Stats Logic
    final pendingCount = requests
        .where((r) => r.status == ProcurementStatus.pending)
        .length;
    final inReviewCount = requests
        .where((r) => r.status == ProcurementStatus.purchased)
        .length;
    final rejectedCount = requests
        .where((r) => r.status == ProcurementStatus.rejected)
        .length;

    // Urgent Logic
    final urgentItems = requests.where((r) {
      final isPendingOld =
          r.status == ProcurementStatus.pending &&
          DateTime.now().difference(r.createdAt).inDays > 3;
      return r.status == ProcurementStatus.rejected || isPendingOld;
    }).toList();

    // Financial Logic (Current Calendar Month only)
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final verifiedRequests = requests.where((r) {
      // Only count post-purchase positive statuses
      final isPostPurchase =
          r.status == ProcurementStatus.purchased ||
          r.status == ProcurementStatus.verified ||
          r.status == ProcurementStatus.stocked ||
          r.status == ProcurementStatus.in_transit ||
          r.status == ProcurementStatus.delivered;
      if (!isPostPurchase) return false;
      // Scope to current month using verifiedAt if set, else createdAt
      final dateToCheck = r.verifiedAt ?? r.createdAt;
      return dateToCheck.isAfter(
            monthStart.subtract(const Duration(seconds: 1)),
          ) &&
          dateToCheck.isBefore(monthEnd);
    });

    final monthlySpent = verifiedRequests
        .fold<double>(0, (sum, r) => sum + r.totalSpent);

    return Column(
      children: [
        // Stats Row
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.cardColor,
                theme.cardColor.withValues(alpha: 0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                context,
                'To Buy',
                '$pendingCount',
                AppColors.purchaserOrange,
              ),
              _buildStatItem(
                context,
                'In Review',
                '$inReviewCount',
                Colors.blue,
              ),
              _buildStatItem(context, 'Rejected', '$rejectedCount', Colors.red),
            ],
          ),
        ),

        // Urgent Tasks Section (If any)
        if (urgentItems.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Urgent Attention',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FrostedPanel(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: urgentItems
                  .take(3)
                  .map((item) => _buildUrgentItemRow(context, item, theme))
                  .toList(),
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Financial Overview Card
        FrostedPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Monthly Spending',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    DateFormat('MMMM yyyy').format(now),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.disabledColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Rs. ${(monthlySpent / 1000).toStringAsFixed(1)}K',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'spent this month',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: verifiedRequests.isEmpty
                      ? 0.0
                      : (monthlySpent /
                                (verifiedRequests.fold<double>(
                                  0,
                                  (s, r) => s + r.budgetLimit,
                                )))
                            .clamp(0.0, 1.0),
                  backgroundColor: theme.dividerColor.withValues(alpha: 0.2),
                  color: Colors.green,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                  'Purchases verified this month.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.disabledColor,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildUrgentItemRow(
    BuildContext context,
    ProcurementRequest request,
    ThemeData theme,
  ) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.priority_high, size: 16, color: Colors.red),
      ),
      title: Text(
        request.packName,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(
        request.status == ProcurementStatus.rejected
            ? 'Rejected: ${request.adminRemarks ?? "Check details"}'
            : 'Pending > 3 Days',
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: () => widget.onSectionChange(PurchaserSection.procurement),
    );
  }

  Widget _buildActivityItem(
    BuildContext context,
    Map<String, dynamic> data,
    ThemeData theme,
  ) {
    final title = data['title'] ?? 'Notification';
    final message = data['message'] ?? '';
    final timestamp =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final isNew = !(data['isRead'] ?? false);

    IconData icon;
    Color color;

    if (title.contains('Verified') || title.contains('Approved')) {
      icon = Icons.check_circle_outline;
      color = Colors.green;
    } else if (title.contains('Rejected') || title.contains('Declined')) {
      icon = Icons.highlight_off;
      color = Colors.red;
    } else if (title.contains('New Request')) {
      icon = Icons.add_shopping_cart;
      color = AppColors.purchaserOrange;
    } else {
      icon = Icons.notifications_outlined;
      color = Colors.blue;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: isNew ? 1.0 : 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNew ? color.withValues(alpha: 0.3) : Colors.transparent,
          width: 1,
        ),
        boxShadow: isNew
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isNew ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isNotEmpty)
              Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              _getTimeAgo(timestamp),
              style: TextStyle(fontSize: 10, color: theme.disabledColor),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  String _getTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
