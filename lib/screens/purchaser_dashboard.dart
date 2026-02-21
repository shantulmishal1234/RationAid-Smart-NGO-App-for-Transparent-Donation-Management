import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Purchaser/models/purchaser_enums.dart';
import 'package:ration_aid/screens/Purchaser/sections/purchaser_profile_section.dart';
import 'package:ration_aid/screens/Purchaser/widgets/purchaser_bottom_nav.dart';
import 'package:ration_aid/screens/Purchaser/widgets/purchaser_scaffold.dart';
import 'package:ration_aid/screens/Purchaser/views/home_view.dart';
import 'package:ration_aid/screens/Purchaser/views/procurement_view.dart';
import 'package:ration_aid/screens/Purchaser/views/inventory_view.dart';
import 'package:ration_aid/screens/Purchaser/views/history_view.dart';
import 'package:ration_aid/screens/Purchaser/views/notifications_view.dart';
import 'package:ration_aid/screens/Purchaser/views/reports_view.dart';
import 'package:ration_aid/services/notification_service.dart';

class PurchaserDashboard extends StatefulWidget {
  const PurchaserDashboard({super.key});

  @override
  State<PurchaserDashboard> createState() => _PurchaserDashboardState();
}

class _PurchaserDashboardState extends State<PurchaserDashboard> {
  PurchaserSection _currentSection = PurchaserSection.dashboard;

  final Map<PurchaserSection, String> _titles = {
    PurchaserSection.dashboard: 'Purchaser Dashboard',
    PurchaserSection.procurement: 'Procurement',
    PurchaserSection.inventory: 'Inventory & Stock',
    PurchaserSection.history: 'Purchase History',
    PurchaserSection.notifications: 'Notifications',
    PurchaserSection.reports: 'Reports & Analytics',
    PurchaserSection.profile: 'My Profile',
  };

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return PurchaserScaffold(
      title: _titles[_currentSection]!,
      showBackButton: false,
      useSafeArea: false,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 80),
            child: _buildBody(),
          ),
        ],
      ),
      bottomNavigationBar: StreamBuilder<int>(
        // Stream unread notification count so the badge auto-updates in real time
        stream: uid == null
            ? Stream.value(0)
            : NotificationService.streamPurchaserNotifications(uid).map(
                (snap) => snap.docs.where((d) => d['isRead'] != true).length,
              ),
        initialData: 0,
        builder: (context, snap) {
          return PurchaserBottomNav(
            currentSection: _currentSection,
            unreadNotificationCount: snap.data ?? 0,
            onSectionChanged: (section) {
              setState(() {
                _currentSection = section;
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    return SafeArea(bottom: false, child: _buildSectionView());
  }

  Widget _buildSectionView() {
    switch (_currentSection) {
      case PurchaserSection.dashboard:
        return PurchaserHomeView(
          onSectionChange: (section) =>
              setState(() => _currentSection = section),
        );
      case PurchaserSection.procurement:
        return const ProcurementView();
      case PurchaserSection.inventory:
        return const InventoryView();
      case PurchaserSection.history:
        return const HistoryView();
      case PurchaserSection.notifications:
        return PurchaserNotificationsView(
          onSectionChange: (section) =>
              setState(() => _currentSection = section),
        );
      case PurchaserSection.reports:
        return const ReportsView();
      case PurchaserSection.profile:
        return const PurchaserProfileSection();
    }
  }
}
