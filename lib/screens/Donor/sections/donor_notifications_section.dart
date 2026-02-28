import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/notification_model.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:ration_aid/services/donation_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Donor Notifications Section - Display all notifications
class DonorNotificationsSection extends StatelessWidget {
  const DonorNotificationsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with Mark All Read
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Notifications',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (userId != null)
                TextButton.icon(
                  onPressed: () async {
                    await NotificationService.markAllUserNotificationsAsRead(
                      userId,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All marked as read')),
                      );
                    }
                  },
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text(
                    'Mark All Read',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.donorGreen,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Stay updated on your donations',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),

          // Notifications list
          Expanded(
            child: userId == null
                ? const Center(child: Text('Please log in'))
                : StreamBuilder(
                    stream: NotificationService.streamUserNotifications(userId),
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
                                Icons.notifications_outlined,
                                size: 80,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No notifications yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final notification = AppNotification.fromFirestore(
                            docs[index],
                          );
                          return _NotificationCard(notification: notification);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Notification Card Widget
class _NotificationCard extends StatelessWidget {
  final AppNotification notification;

  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: notification.isRead
            ? Theme.of(context).cardColor
            : (Theme.of(context).brightness == Brightness.dark
                  ? AppColors.donorGreen.withValues(alpha: 0.1)
                  : Colors.green[50]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (!notification.isRead) {
              await NotificationService.markAsRead(notification.id);
            }
            // Navigate to donation if this is a donation-related notification
            if (notification.hasAction &&
                notification.actionType == 'donation_status' &&
                context.mounted) {
              try {
                final donation = await DonationService().getDonationById(
                  notification.actionId!,
                );
                if (donation != null && context.mounted) {
                  Navigator.pushNamed(
                    context,
                    '/donation-tracking',
                    arguments: donation,
                  );
                }
              } catch (_) {}
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Unread indicator
                if (!notification.isRead)
                  Container(
                    margin: const EdgeInsets.only(top: 4, right: 12),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.donorGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight: notification.isRead
                              ? FontWeight.w500
                              : FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.message,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        notification.timeAgo,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                // Icon
                Icon(
                  notification.isBroadcast
                      ? Icons.campaign
                      : Icons.volunteer_activism,
                  color: AppColors.donorGreen.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
