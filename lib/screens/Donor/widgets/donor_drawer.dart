import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Donor/models/donor_enums.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Donor Dashboard navigation drawer
/// Matches the style and structure of Admin drawer
class DonorDrawer extends StatelessWidget {
  final User? user;
  final DonorSection currentSection;
  final ValueChanged<DonorSection> onSectionChanged;

  const DonorDrawer({
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
                  colors: [AppColors.donorGreen, AppColors.accentGreen],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.volunteer_activism,
                  color: AppColors.donorGreen,
                  size: 32,
                ),
              ),
              accountName: Text(
                user?.displayName ?? 'Donor',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              accountEmail: Text(user?.email ?? ''),
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.dashboard_rounded,
              label: 'Dashboard',
              section: DonorSection.dashboard,
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.family_restroom,
              label: 'Explore Families',
              section: DonorSection.exploreFamilies,
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.volunteer_activism,
              label: 'My Donations',
              section: DonorSection.myDonations,
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.notifications,
              label: 'Notifications',
              section: DonorSection.notifications,
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.person,
              label: 'Profile',
              section: DonorSection.profile,
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Ration Aid'),
              onTap: () {
                // TODO: Show about dialog
              },
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
    required DonorSection section,
  }) {
    final isSelected = currentSection == section;

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AppColors.donorGreen : Colors.grey[700],
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? AppColors.donorGreen : Colors.grey[800],
        ),
      ),
      selected: isSelected,
      selectedTileColor: AppColors.donorGreen.withValues(alpha: 0.08),
      onTap: () {
        onSectionChanged(section);
        Navigator.pop(context);
      },
    );
  }
}
