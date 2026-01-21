import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Donor/models/donor_enums.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_bottom_nav.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_scaffold.dart';

import 'package:ration_aid/screens/Donor/sections/donor_dashboard_section.dart';
import 'package:ration_aid/screens/Donor/sections/explore_families_section.dart';
import 'package:ration_aid/screens/Donor/sections/my_donations_section.dart';
import 'package:ration_aid/screens/Donor/sections/donor_notifications_section.dart';
import 'package:ration_aid/screens/Donor/sections/donor_profile_section.dart';
import 'package:ration_aid/screens/Donor/donor_routes.dart';

/// Donor Dashboard - Main screen for donor users
/// Matches Admin Dashboard structure with section-based routing
class DonorDashboard extends StatefulWidget {
  const DonorDashboard({super.key});

  @override
  State<DonorDashboard> createState() => _DonorDashboardState();
}

class _DonorDashboardState extends State<DonorDashboard> {
  DonorSection _currentSection = DonorSection.dashboard;

  /// Public method to switch sections (called from child widgets)
  void switchSection(DonorSection section) {
    setState(() {
      _currentSection = section;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Navigator(
      onGenerateRoute: (settings) {
        // Handle child routes
        final route = DonorRoutes.generateRoute(settings);
        if (route != null) return route;

        // Default to main dashboard scaffold
        return MaterialPageRoute(builder: (_) => _buildDashboardScaffold(user));
      },
    );
  }

  Widget _buildDashboardScaffold(User? user) {
    return DonorScaffold(
      title: 'Donor Dashboard',
      showBackButton: false,
      bottomNavigationBar: DonorBottomNav(
        currentSection: _currentSection,
        onSectionChanged: (section) {
          setState(() => _currentSection = section);
        },
      ),
      body: _buildCurrentSection(),
    );
  }

  Widget _buildCurrentSection() {
    switch (_currentSection) {
      case DonorSection.dashboard:
        return const DonorDashboardSection();

      case DonorSection.exploreFamilies:
        return const ExploreFamiliesSection();

      case DonorSection.myDonations:
        return const MyDonationsSection();

      case DonorSection.notifications:
        return const DonorNotificationsSection();

      case DonorSection.profile:
        return const DonorProfileSection();
    }
  }
}
