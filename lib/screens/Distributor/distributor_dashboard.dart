import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ration_aid/screens/Distributor/sections/assignments_section.dart';
import 'package:ration_aid/screens/Distributor/sections/distributor_profile_section.dart';
import 'package:ration_aid/screens/Distributor/sections/performance_section.dart';
import 'package:ration_aid/screens/Distributor/widgets/distributor_bottom_nav.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

class DistributorDashboard extends StatefulWidget {
  const DistributorDashboard({super.key});

  @override
  State<DistributorDashboard> createState() => _DistributorDashboardState();
}

class _DistributorDashboardState extends State<DistributorDashboard> {
  DistributorSection _currentSection = DistributorSection.deliveries;
  int _pendingOffline = 0;

  @override
  void initState() {
    super.initState();
    _init();
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

  String get _title {
    switch (_currentSection) {
      case DistributorSection.deliveries:
        return 'My Deliveries';
      case DistributorSection.performance:
        return 'Performance';
      case DistributorSection.profile:
        return 'Profile';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            if (_currentSection == DistributorSection.deliveries)
              Text(
                'Welcome, ${user?.displayName?.split(' ').first ?? 'Distributor'} 👋',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        backgroundColor: AppColors.volunteerBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1565C0), AppColors.volunteerBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          // Offline pending badge
          if (_pendingOffline > 0)
            Tooltip(
              message: '$_pendingOffline delivery proof(s) pending sync',
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepOrange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 14, color: Colors.white),
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
      ),
      body: IndexedStack(
        index: _currentSection.index,
        children: const [
          AssignmentsSection(),
          PerformanceSection(),
          DistributorProfileSection(),
        ],
      ),
      bottomNavigationBar: DistributorBottomNav(
        currentSection: _currentSection,
        onSectionChanged: (s) => setState(() => _currentSection = s),
      ),
    );
  }
}
