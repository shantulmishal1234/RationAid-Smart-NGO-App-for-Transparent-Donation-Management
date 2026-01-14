import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/theme/app_colors.dart';

class NotificationsCenterScreen extends StatefulWidget {
  const NotificationsCenterScreen({super.key});

  @override
  State<NotificationsCenterScreen> createState() =>
      _NotificationsCenterScreenState();
}

class _NotificationsCenterScreenState extends State<NotificationsCenterScreen> {
  // DEMO static notification data
  final List<Map<String, dynamic>> _demoNotifications = [
    {
      'title': 'New Donation Verification Request',
      'body':
          'Donor Zainab Bashir has uploaded proof for a Rs. 5,000 donation. Please review and verify.',
      'isRead': false,
      'createdAt': DateTime.now().subtract(const Duration(hours: 1)),
    },
    {
      'title': 'Volunteer Missed Delivery',
      'body':
          'Volunteer Ali Raza missed the scheduled delivery for Family #102 in Shahdara.',
      'isRead': false,
      'createdAt': DateTime.now().subtract(const Duration(hours: 3)),
    },
    {
      'title': 'New Household Application',
      'body':
          'Family of Haji Usman Khan from Gulberg, Lahore has registered. Please review their application status.',
      'isRead': true,
      'createdAt': DateTime.now().subtract(const Duration(days: 1)),
    },
    {
      'title': 'Low-Stock Alert: Flour',
      'body':
          'Flour stock is critically low (only 2 kg remaining) at the Johar Town warehouse. Please refill urgently.',
      'isRead': false,
      'createdAt': DateTime.now().subtract(const Duration(hours: 12)),
    },
    {
      'title': 'System Error Logged',
      'body':
          'Audit log recorded: Failed to sync donor records for Abdul Hameed. Check system status and retry.',
      'isRead': true,
      'createdAt': DateTime.now().subtract(const Duration(days: 2)),
    },
    {
      'title': 'EMERGENCY: Heatwave Alert',
      'body':
          'All teams: Prioritize water distribution today in Barkat Market, Shahdara and Township areas.',
      'isRead': false,
      'createdAt': DateTime.now().subtract(const Duration(minutes: 30)),
    },
    {
      'title': 'Delivery Completed',
      'body':
          'Volunteer Fatima Jaleel has successfully delivered ration to Family #110 in Model Town.',
      'isRead': true,
      'createdAt': DateTime.now().subtract(const Duration(hours: 20)),
    },
    {
      'title': 'Donor Impact Summary',
      'body':
          'Thank you message prepared for donor Abdul Rehman: “Your support helped 18 families this month.”',
      'isRead': false,
      'createdAt': DateTime.now().subtract(const Duration(hours: 5)),
    },
  ];

  // Simple helper for sidebar badge (export this if needed)
  int getDemoUnreadCount() {
    return _demoNotifications.where((n) => n['isRead'] == false).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Notifications (demo)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Small header inside body if you like
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent activity',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  itemCount: _demoNotifications.length,
                  itemBuilder: (context, index) {
                    final data = _demoNotifications[index];
                    final isRead = data['isRead'] ?? false;
                    final title = data['title'] ?? 'Notification';
                    final body = data['body'] ?? '';
                    final createdAt = data['createdAt'] as DateTime?;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      color: isRead ? Colors.white : Colors.blue[50],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isRead
                              ? Colors.grey[300]
                              : Colors.blue,
                          child: Icon(
                            isRead
                                ? Icons.notifications_none
                                : Icons.notifications_active,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontWeight: isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              body,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (createdAt != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                _formatTime(createdAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: isRead
                            ? null
                            : const Icon(
                                Icons.fiber_new,
                                color: Colors.orange,
                                size: 18,
                              ),
                        onTap: () => _showNotificationDetail(
                          title: title,
                          body: body,
                          createdAt: createdAt,
                          isRead: isRead,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, yyyy').format(date);
  }

  void _showNotificationDetail({
    required String title,
    required String body,
    DateTime? createdAt,
    required bool isRead,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isRead ? Icons.notifications_none : Icons.notifications_active,
              color: AppColors.primaryBlue,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: const TextStyle(fontSize: 14, height: 1.4)),
            if (createdAt != null) ...[
              const SizedBox(height: 16),
              Text(
                DateFormat('MMM d, yyyy · h:mm a').format(createdAt),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // This can be used for the badge in the sidebar, for example:
  // final int unread = getDemoUnreadCount();
}
