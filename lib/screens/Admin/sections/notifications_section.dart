import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/widgets/notification_card.dart';
import 'package:ration_aid/screens/Admin/Notifications/admin_send_notification_screen.dart';
import 'package:ration_aid/screens/Admin/Notifications/notifications_center_screen.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Notifications section for sending and viewing notifications
class NotificationsSection extends StatelessWidget {
  const NotificationsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('notifications'),
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFF7FAFF), Color(0xFFF3F7FF)],
        ),
      ),
      child: Column(
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
                  color: AppColors.textPrimary,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Send and manage role-based notifications and alerts.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grid inside card container
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
              padding: const EdgeInsets.all(16),
              child: GridView.count(
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
      ),
    );
  }
}
