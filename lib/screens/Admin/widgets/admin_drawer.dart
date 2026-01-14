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
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AdminColors.primaryBlue, AdminColors.accentGreen],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.admin_panel_settings,
                  color: AdminColors.primaryBlue,
                  size: 32,
                ),
              ),
              accountName: Text(
                user?.displayName ?? 'Admin',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              accountEmail: Text(user?.email ?? ''),
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
              leading: const Icon(Icons.info_outline),
              title: const Text('About Ration Aid'),
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

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AdminColors.primaryBlue : Colors.grey[700],
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? AdminColors.primaryBlue : Colors.grey[800],
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
