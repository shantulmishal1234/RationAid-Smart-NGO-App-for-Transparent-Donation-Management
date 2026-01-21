import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_bottom_nav.dart';
import 'package:ration_aid/screens/Admin/widgets/floating_action_menu.dart';
import 'package:ration_aid/screens/Admin/sections/dashboard_section.dart';
import 'package:ration_aid/screens/Admin/sections/households_section.dart';
import 'package:ration_aid/screens/Admin/sections/donations_section.dart';
import 'package:ration_aid/screens/Admin/sections/hrm_section.dart';
import 'package:ration_aid/screens/Admin/sections/reports_section.dart';
import 'package:ration_aid/screens/Admin/sections/notifications_section.dart';
import 'package:ration_aid/screens/Admin/sections/profile_section.dart';
import 'package:ration_aid/screens/Admin/Audit Trail/audit_trail_screen.dart';
import 'package:ration_aid/screens/Startup & Authentication/auth_screen.dart';
import 'package:ration_aid/services/auth_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _authService = AuthService();
  AdminSection _currentSection = AdminSection.dashboard;
  bool _showFloatingMenu = false;

  // Filters for various sections
  DonationStatusFilter _donationFilter = DonationStatusFilter.all;
  String _hrmSelectedRole = 'all';

  void _toggleFloatingMenu() {
    setState(() {
      _showFloatingMenu = !_showFloatingMenu;
    });
  }

  void _handleSectionChange(AdminSection section) {
    setState(() {
      _currentSection = section;
      _showFloatingMenu = false; // Close menu when changing section
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        titleSpacing: 16,
        title: Text(
          'Admin Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        // Gradient app bar background
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      theme.scaffoldBackgroundColor,
                      theme.scaffoldBackgroundColor,
                    ]
                  : [AppColors.primaryBlue, AppColors.accentGreen],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: isDark
                ? Border(bottom: BorderSide(color: theme.dividerColor))
                : null,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: () {
              setState(() {
                _currentSection = AdminSection.notifications;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await _authService.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  // Fade + slight slide from bottom-right
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.02, 0.02),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _buildCurrentSection(),
              ),
            ),
          ),
          // Floating action menu overlay
          if (_showFloatingMenu)
            FloatingActionMenu(
              onDismiss: () {
                setState(() {
                  _showFloatingMenu = false;
                });
              },
              onSectionChanged: _handleSectionChange,
            ),
        ],
      ),
      bottomNavigationBar: AdminBottomNav(
        currentSection: _currentSection,
        onSectionChanged: _handleSectionChange,
        onMoreTapped: _toggleFloatingMenu,
      ),
    );
  }

  Widget _buildCurrentSection() {
    switch (_currentSection) {
      case AdminSection.dashboard:
        return const DashboardSection();

      case AdminSection.households:
        return const HouseholdsSection();

      case AdminSection.donations:
        return DonationsSection(
          donationFilter: _donationFilter,
          onFilterChanged: (filter) {
            setState(() {
              _donationFilter = filter;
            });
          },
        );

      case AdminSection.hrm:
        return HrmSection(
          hrmSelectedRole: _hrmSelectedRole,
          onRoleChanged: (role) {
            setState(() {
              _hrmSelectedRole = role;
            });
          },
        );

      case AdminSection.audit:
        return const AuditTrailScreen();

      case AdminSection.reports:
        return ReportsSection(
          onSectionChanged: (section) {
            setState(() {
              _currentSection = section;
            });
          },
        );

      case AdminSection.notifications:
        return const NotificationsSection();

      case AdminSection.profile:
        return const AdminProfileSection();
    }
  }
}
