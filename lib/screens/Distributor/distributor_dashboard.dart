import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/screens/Distributor/sections/assignments_section.dart';
import 'package:ration_aid/screens/Distributor/sections/distributor_profile_section.dart';
import 'package:ration_aid/screens/Distributor/sections/performance_section.dart';
import 'package:ration_aid/screens/Distributor/sections/distributor_history_section.dart';
import 'package:ration_aid/screens/Distributor/widgets/distributor_bottom_nav.dart';
import 'package:ration_aid/screens/Distributor/Notifications/distributor_notifications_screen.dart';
import 'package:ration_aid/screens/Distributor/views/distributor_home_view.dart';
import 'package:ration_aid/screens/Distributor/views/distributor_reports_view.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:ration_aid/screens/Distributor/widgets/distributor_scaffold.dart';

class DistributorDashboard extends StatefulWidget {
  const DistributorDashboard({super.key});

  @override
  State<DistributorDashboard> createState() => _DistributorDashboardState();
}

class _DistributorDashboardState extends State<DistributorDashboard>
    with WidgetsBindingObserver {
  DistributorSection _currentSection = DistributorSection.dashboard;
  int _pendingOffline = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check offline queue whenever the app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  Future<void> _init() async {
    // Sync any offline proofs when app loads
    final synced = await DeliveryService.syncOfflineProofs();
    if (synced > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $synced offline proof(s) synced successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
    // Check how many remain offline
    final count = await DeliveryService.getPendingOfflineCount();
    if (mounted) setState(() => _pendingOffline = count);
  }

  final Map<DistributorSection, String> _titles = {
    DistributorSection.dashboard: 'Distributor Dashboard',
    DistributorSection.deliveries: 'My Deliveries',
    DistributorSection.history: 'Delivery History',
    DistributorSection.notifications: 'Notifications',
    DistributorSection.performance: 'Performance',
    DistributorSection.reports: 'Reports & Analytics',
    DistributorSection.profile: 'Profile',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return StreamBuilder<DocumentSnapshot>(
      stream: uid == null
          ? const Stream.empty()
          : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>?;
        final isSupervisor = userData?['isSupervisor'] ?? false;

        return DistributorScaffold(
          title: _titles[_currentSection]!,
          showBackButton: false,
          useSafeArea: false,
          actions: [
            // Offline pending badge
            if (_pendingOffline > 0)
              Tooltip(
                message: '$_pendingOffline delivery proof(s) pending sync',
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$_pendingOffline',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          body: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 80),
                child: SafeArea(
                  bottom: false,
                  child: _buildSectionView(isSupervisor),
                ),
              ),
            ],
          ),
          bottomNavigationBar: uid == null
              ? DistributorBottomNav(
                  currentSection: _currentSection,
                  unreadNotificationCount: 0,
                  isSupervisor: false,
                  onSectionChanged: (s) => setState(() => _currentSection = s),
                )
              : StreamBuilder<int>(
                  stream: NotificationService.getDistributorUnreadCountStream(
                    uid,
                  ),
                  builder: (context, snapshot) {
                    final unreadCount = snapshot.data ?? 0;
                    return DistributorBottomNav(
                      currentSection: _currentSection,
                      isSupervisor: isSupervisor,
                      unreadNotificationCount: unreadCount,
                      onSectionChanged: (s) =>
                          setState(() => _currentSection = s),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildSectionView(bool isSupervisor) {
    switch (_currentSection) {
      case DistributorSection.dashboard:
        return DistributorHomeView(
          isSupervisor: isSupervisor,
          onSectionChange: (section) =>
              setState(() => _currentSection = section),
        );
      case DistributorSection.deliveries:
        return AssignmentsSection(isSupervisor: isSupervisor);
      case DistributorSection.history:
        return DistributorHistorySection(isSupervisor: isSupervisor);
      case DistributorSection.notifications:
        return const DistributorNotificationScreen();
      case DistributorSection.performance:
        return const PerformanceSection();
      case DistributorSection.reports:
        return isSupervisor
            ? const DistributorReportsView()
            : const SizedBox.shrink();
      case DistributorSection.profile:
        return const DistributorProfileSection();
    }
  }
}
