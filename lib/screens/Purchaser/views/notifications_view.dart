import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/notification_model.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Purchaser/models/purchaser_enums.dart';
import 'package:ration_aid/widgets/frosted_panel.dart';

/// Purchaser Notifications View - Display all notifications
class PurchaserNotificationsView extends StatelessWidget {
  final ValueChanged<PurchaserSection>? onSectionChange;

  const PurchaserNotificationsView({super.key, this.onSectionChange});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
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
              if (userId != null)
                TextButton.icon(
                  onPressed: () async {
                    await NotificationService.markAllUserNotificationsAsRead(
                      userId,
                    );
                  },
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text(
                    'Mark All Read',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.purchaserOrange,
                  ),
                ),
            ],
          ),
        ),

        // Notifications list
        Expanded(
          child: userId == null
              ? const Center(child: Text('Please log in'))
              : FrostedPanel(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: EdgeInsets.zero,
                  child: StreamBuilder(
                    stream: NotificationService.streamPurchaserNotifications(
                      userId,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Could not load notifications',
                            style: TextStyle(color: Colors.red[400]),
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return _buildEmptyState(context);
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final notification = AppNotification.fromFirestore(
                            docs[index],
                          );
                          return _NotificationCard(
                            notification: notification,
                            onSectionChange: onSectionChange,
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          Text(
            'You\'re all caught up!',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
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
  final ValueChanged<PurchaserSection>? onSectionChange;

  const _NotificationCard({required this.notification, this.onSectionChange});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.isRead;

    return Container(
      decoration: BoxDecoration(
        color: isUnread
            ? AppColors.purchaserOrange.withValues(alpha: 0.05)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUnread
              ? AppColors.purchaserOrange.withValues(alpha: 0.3)
              : theme.dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: () async {
          if (isUnread) {
            await NotificationService.markPurchaserNotificationAsRead(
              notification.id,
            );
          }

          // Navigation Logic
          if (onSectionChange != null) {
            if (notification.actionType == 'new_request') {
              onSectionChange!(PurchaserSection.procurement);
            } else if (notification.actionType == 'procurement_verified') {
              onSectionChange!(
                PurchaserSection.inventory,
              ); // Verified = Inventory
            } else if (notification.actionType == 'procurement_rejected') {
              onSectionChange!(PurchaserSection.procurement);
            }
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isUnread
                      ? AppColors.purchaserOrange.withValues(alpha: 0.1)
                      : theme.scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getNotificationIcon(notification),
                  color: isUnread
                      ? AppColors.purchaserOrange
                      : theme.iconTheme.color?.withValues(alpha: 0.6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: isUnread
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 14,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          notification.timeAgo,
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
                      notification.message,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getNotificationIcon(AppNotification notification) {
    if (notification.actionType == 'procurement_verified') {
      return Icons.check_circle_outline;
    } else if (notification.actionType == 'procurement_rejected') {
      return Icons.cancel_outlined;
    } else if (notification.isBroadcast) {
      return Icons.campaign_outlined;
    } else if (notification.title.contains('Approved')) {
      return Icons.check_circle_outline;
    }
    return Icons.notifications_none;
  }
}
