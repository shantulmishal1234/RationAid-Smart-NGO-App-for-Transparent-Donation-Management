import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:ration_aid/screens/Admin/Notifications/admin_send_notification_screen.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';

class NotificationsCenterScreen extends StatefulWidget {
  const NotificationsCenterScreen({super.key});

  @override
  State<NotificationsCenterScreen> createState() =>
      _NotificationsCenterScreenState();
}

class _NotificationsCenterScreenState extends State<NotificationsCenterScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (currentUser == null) {
      return const AdminScaffold(
        title: 'Notifications',
        body: Center(child: Text('Please login to view notifications')),
      );
    }

    return AdminScaffold(
      title: 'Notifications',
      actions: [
        IconButton(
          icon: const Icon(Icons.send),
          tooltip: 'Send Notification',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminSendNotificationScreen(),
              ),
            );
          },
        ),
      ],
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('admin_notifications')
            .orderBy('createdAt', descending: true)
            .snapshots(),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: theme.disabledColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.disabledColor,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead =
                  (data['readBy'] as List<dynamic>?)?.contains(
                    currentUser?.uid,
                  ) ??
                  false;
              final createdAt = data['createdAt'] as Timestamp?;

              return _NotificationTile(
                title: data['title'] ?? 'No Title',
                body: data['message'] ?? data['body'] ?? 'No Body',
                createdAt: createdAt?.toDate(),
                isRead: isRead,
                onTap: () {
                  if (!isRead) {
                    NotificationService.markAsRead(doc.id);
                  }
                  _showNotificationDetails(
                    context,
                    data['title'] ?? 'No Title',
                    data['message'] ?? data['body'] ?? 'No Body',
                    createdAt?.toDate(),
                  );
                },
              );
            },
          );
        },
      ),
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
                style: Theme.of(context).textTheme.bodySmall,
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

class _NotificationTile extends StatelessWidget {
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool isRead;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: FrostedPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isRead
                    ? theme.disabledColor.withOpacity(0.1)
                    : theme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRead
                    ? Icons.notifications_outlined
                    : Icons.notifications_active,
                color: isRead ? theme.disabledColor : theme.primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: isRead
                                ? FontWeight.normal
                                : FontWeight.bold,
                            color: isRead
                                ? theme.textTheme.bodyMedium?.color
                                      ?.withOpacity(0.7)
                                : theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      if (createdAt != null)
                        Text(
                          _formatTime(createdAt!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: theme.disabledColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
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

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('MMM d').format(date);
  }
}
