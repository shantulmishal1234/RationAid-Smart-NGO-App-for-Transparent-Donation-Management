import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_drawer.dart';
import 'package:ration_aid/screens/Admin/sections/dashboard_section.dart';
import 'package:ration_aid/screens/Admin/sections/households_section.dart';
import 'package:ration_aid/screens/Admin/sections/donations_section.dart';
import 'package:ration_aid/screens/Admin/sections/hrm_section.dart';
import 'package:ration_aid/screens/Admin/sections/reports_section.dart';
import 'package:ration_aid/screens/Admin/sections/notifications_section.dart';
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

  // Filters for various sections
  DonationStatusFilter _donationFilter = DonationStatusFilter.all;
  String _hrmSelectedRole = 'all';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        // Gradient app bar background
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryBlue, AppColors.accentGreen],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        actions: [
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
      drawer: AdminDrawer(
        user: user,
        currentSection: _currentSection,
        onSectionChanged: (section) {
          setState(() => _currentSection = section);
        },
      ),
      body: SafeArea(
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
    }
  }
}
