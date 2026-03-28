import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Purchaser/models/purchaser_enums.dart';
import 'package:ration_aid/screens/Purchaser/sections/purchaser_profile_section.dart';
import 'package:ration_aid/screens/Purchaser/widgets/purchaser_bottom_nav.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/screens/Purchaser/widgets/purchaser_scaffold.dart';
import 'package:ration_aid/screens/Purchaser/views/home_view.dart';
import 'package:ration_aid/screens/Purchaser/views/procurement_view.dart';
import 'package:ration_aid/screens/Purchaser/views/inbound_pickups_view.dart';
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
  Stream<DocumentSnapshot>? _userStream;
  Stream<int>? _unreadCountStream;
  String? _currentUid;

  final Map<PurchaserSection, String> _titles = {
    PurchaserSection.dashboard: 'Purchaser Dashboard',
    PurchaserSection.procurement: 'Procurement',
    PurchaserSection.inboundPickups: 'Inbound Pickups',
    PurchaserSection.inventory: 'Inventory & Stock',
    PurchaserSection.history: 'Purchase History',
    PurchaserSection.notifications: 'Notifications',
    PurchaserSection.reports: 'Reports & Analytics',
    PurchaserSection.profile: 'My Profile',
  };

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  void _initStreams() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid != _currentUid) {
      _currentUid = uid;
      _userStream = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots();
      _unreadCountStream = NotificationService.getPurchaserUnreadCountStream(
        uid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != _currentUid) {
      _initStreams();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: _userStream ?? const Stream.empty(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>?;
        final isSupervisor = userData?['isSupervisor'] ?? false;

        return PurchaserScaffold(
          title: _titles[_currentSection]!,
          showBackButton: false,
          useSafeArea: false,
          body: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 80),
                child: _buildBody(isSupervisor),
              ),
            ],
          ),
          bottomNavigationBar: StreamBuilder<int>(
            stream: _unreadCountStream ?? Stream.value(0),
            initialData: 0,
            builder: (context, snap) {
              return PurchaserBottomNav(
                currentSection: _currentSection,
                isSupervisor: isSupervisor,
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
      },
    );
  }

  Widget _buildBody(bool isSupervisor) {
    return SafeArea(bottom: false, child: _buildSectionView(isSupervisor));
  }

  Widget _buildSectionView(bool isSupervisor) {
    switch (_currentSection) {
      case PurchaserSection.dashboard:
        return PurchaserHomeView(
          isSupervisor: isSupervisor,
          onSectionChange: (section) =>
              setState(() => _currentSection = section),
        );
      case PurchaserSection.procurement:
        return ProcurementView(isSupervisor: isSupervisor);
      case PurchaserSection.inboundPickups:
        return const InboundPickupsView();
      case PurchaserSection.inventory:
        return const InventoryView();
      case PurchaserSection.history:
        return HistoryView(isSupervisor: isSupervisor);
      case PurchaserSection.notifications:
        return PurchaserNotificationsView(
          onSectionChange: (section) =>
              setState(() => _currentSection = section),
        );
      case PurchaserSection.reports:
        return isSupervisor ? const ReportsView() : const SizedBox.shrink();
      case PurchaserSection.profile:
        return const PurchaserProfileSection();
    }
  }
}
