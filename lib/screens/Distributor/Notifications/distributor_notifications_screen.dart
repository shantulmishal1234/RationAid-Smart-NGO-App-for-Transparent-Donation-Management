import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/services/notification_service.dart';

import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/widgets/frosted_panel.dart';

class DistributorNotificationScreen extends StatefulWidget {
  const DistributorNotificationScreen({super.key});

  @override
  State<DistributorNotificationScreen> createState() =>
      _DistributorNotificationScreenState();
}

class _DistributorNotificationScreenState
    extends State<DistributorNotificationScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const Center(child: Text('Please login to view notifications'));
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row with Mark All Read
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Notifications',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: 0.5,
                ),
              ),
              if (currentUser != null)
                TextButton.icon(
                  onPressed: () async {
                    await NotificationService.markAllUserNotificationsAsRead(
                      currentUser!.uid,
                    );
                  },
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text(
                    'Mark All Read',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.volunteerBlue,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: FrostedPanel(
              padding: EdgeInsets.zero,
              child: StreamBuilder<QuerySnapshot>(
                stream: NotificationService.streamDistributorNotifications(
                  currentUser!.uid,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No notifications yet',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final isRead = data['isRead'] ?? false;
                      final createdAt = data['createdAt'] as Timestamp?;

                      return _DistributorNotificationTile(
                        title: data['title'] ?? 'No Title',
                        body: data['message'] ?? 'No Message',
                        createdAt: createdAt?.toDate(),
                        isRead: isRead,
                        onTap: () {
                          if (!isRead) {
                            NotificationService.markNotificationAsRead(doc.id);
                          }
                          _showNotificationDetails(
                            context,
                            data['title'] ?? 'No Title',
                            data['message'] ?? 'No Message',
                            createdAt?.toDate(),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showNotificationDetails(
    BuildContext context,
    String title,
    String body,
    DateTime? createdAt,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            if (createdAt != null) ...[
              const SizedBox(height: 16),
              Text(
                DateFormat('MMM d, yyyy · h:mm a').format(createdAt),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
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
}

class _DistributorNotificationTile extends StatelessWidget {
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool isRead;
  final VoidCallback onTap;

  const _DistributorNotificationTile({
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead
              ? Colors.transparent
              : (isDark
                    ? Colors.blue.withValues(alpha: 0.1)
                    : Colors.blue.shade50),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isRead
                    ? theme.disabledColor.withValues(alpha: 0.1)
                    : Colors.blue.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRead
                    ? Icons.notifications_outlined
                    : Icons.notifications_active,
                color: isRead ? theme.disabledColor : Colors.blue,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: isRead
                                ? FontWeight.w600
                                : FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (createdAt != null)
                        Text(
                          _formatTimeAgo(createdAt!),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: isRead ? 0.6 : 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays > 7) {
      return DateFormat('MMM d').format(dateTime);
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'Just now';
    }
  }
}
