import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/widgets/notification_card.dart';
import 'package:ration_aid/screens/Admin/Notifications/admin_send_notification_screen.dart';
import 'package:ration_aid/screens/Admin/Notifications/notifications_center_screen.dart';

/// Notifications section for sending and viewing notifications
class NotificationsSection extends StatelessWidget {
  const NotificationsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Centered title + subtitle
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Notifications management',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Send and manage role-based notifications and alerts.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Grid inside card container
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.96),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: GridView.count(
              padding: const EdgeInsets.only(bottom: 100),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.3,
              children: [
                NotificationCard(
                  icon: Icons.send,
                  title: 'Send notification',
                  description: 'Broadcast to roles or users',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminSendNotificationScreen(),
                      ),
                    );
                  },
                ),
                NotificationCard(
                  icon: Icons.notifications,
                  title: 'View notifications',
                  description: 'See all your notifications',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationsCenterScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
