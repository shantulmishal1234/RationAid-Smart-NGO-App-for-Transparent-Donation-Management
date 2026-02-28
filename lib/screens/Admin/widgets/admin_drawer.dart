import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';

/// Admin Dashboard navigation drawer
class AdminDrawer extends StatelessWidget {
  final User? user;
  final AdminSection currentSection;
  final ValueChanged<AdminSection> onSectionChanged;

  const AdminDrawer({
    super.key,
    required this.user,
    required this.currentSection,
    required this.onSectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          theme.scaffoldBackgroundColor,
                          theme.scaffoldBackgroundColor,
                        ]
                      : [AdminColors.primaryBlue, AdminColors.accentGreen],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: isDark
                    ? Border(bottom: BorderSide(color: theme.dividerColor))
                    : null,
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: theme.cardColor,
                child: const Icon(
                  Icons.admin_panel_settings,
                  color: AdminColors.primaryBlue,
                  size: 32,
                ),
              ),
              accountName: Text(
                user?.displayName ?? 'Admin',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              accountEmail: Text(
                user?.email ?? '',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.dashboard_rounded,
              label: 'Dashboard',
              section: AdminSection.dashboard,
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.family_restroom,
              label: 'Households',
              section: AdminSection.households,
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.volunteer_activism,
              label: 'Donations',
              section: AdminSection.donations,
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.group,
              label: 'HRM (Members)',
              section: AdminSection.hrm,
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.receipt_long,
              label: 'Audit Trail',
              section: AdminSection.audit,
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.bar_chart_rounded,
              label: 'Reports & Analytics',
              section: AdminSection.reports,
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.notifications,
              label: 'Notifications',
              section: AdminSection.notifications,
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.info_outline,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              title: Text(
                'About Ration Aid',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  ListTile _buildDrawerItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required AdminSection section,
  }) {
    final isSelected = currentSection == section;
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected
            ? AdminColors.primaryBlue
            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected
              ? AdminColors.primaryBlue
              : theme.colorScheme.onSurface.withValues(alpha: 0.9),
        ),
      ),
      selected: isSelected,
      selectedTileColor: AdminColors.primaryBlue.withValues(alpha: 0.08),
      onTap: () {
        onSectionChanged(section);
        Navigator.pop(context);
      },
    );
  }
}
