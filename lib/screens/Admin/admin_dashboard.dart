import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_bottom_nav.dart';
import 'package:ration_aid/screens/Admin/sections/dashboard_section.dart';
import 'package:ration_aid/screens/Admin/sections/households_section.dart';
import 'package:ration_aid/screens/Admin/sections/donations_section.dart';
import 'package:ration_aid/screens/Admin/sections/hrm_section.dart';
import 'package:ration_aid/screens/Admin/sections/reports_section.dart';
import 'package:ration_aid/screens/Admin/sections/admin_more_section.dart';
import 'package:ration_aid/screens/Admin/Notifications/notifications_center_screen.dart';
import 'package:ration_aid/screens/Admin/sections/profile_section.dart';
import 'package:ration_aid/screens/Admin/Audit Trail/audit_trail_screen.dart';
import 'package:ration_aid/screens/Admin/FinalApprover/final_approver_screen.dart';
import 'package:ration_aid/screens/Admin/AssistancePacks/pack_management_screen.dart';
import 'package:ration_aid/screens/Admin/Verification/purchase_approval_screen.dart';
import 'package:ration_aid/screens/Admin/Delivery/admin_delivery_management_screen.dart';
import 'package:ration_aid/screens/Admin/Verification/inventory_issues_screen.dart';

import 'package:ration_aid/services/notification_service.dart';

import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  AdminSection _currentSection = AdminSection.dashboard;
  bool _isAuthorized = true; // Assume true until proven otherwise

  // Filters for various sections
  DonationStatusFilter _donationFilter = DonationStatusFilter.all;
  String _hrmSelectedRole = 'all';

  // Optimized streams
  late final Stream<int> _unreadCountStream;

  @override
  void initState() {
    super.initState();
    _verifyAdminRole();
    _unreadCountStream = NotificationService.getUnreadCountStream();
  }

  /// Verify the current user has admin role — prevents unauthorized access
  Future<void> _verifyAdminRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _denyAccess();
      return;
    }
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!userDoc.exists) {
        _denyAccess();
        return;
      }
      final roles = List<String>.from(userDoc.data()?['roles'] ?? []);
      if (!roles.contains('admin') && !roles.contains('ngo_admin')) {
        _denyAccess();
      }
    } catch (_) {
      _denyAccess();
    }
  }

  void _denyAccess() {
    if (!mounted) return;
    setState(() => _isAuthorized = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.red,
        content: Text('⛔ Access denied: Admin role required'),
      ),
    );
    // Instead of pushing to a black screen, sign the user out to trigger DashboardRouter fallback
    FirebaseAuth.instance.signOut();
  }

  void _handleSectionChange(AdminSection section) {
    setState(() {
      _currentSection = section;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Admin Dashboard',
      showBackButton: false,
      actions: [
        StreamBuilder<int>(
          stream: _unreadCountStream,
          builder: (context, snapshot) {
            final unreadCount = snapshot.data ?? 0;
            return Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_active_outlined),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NotificationsCenterScreen(),
                      ),
                    );
                  },
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 4,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(width: 8),
      ],
      body: Stack(
        children: [
          // Main content
          SafeArea(
            top: false,
            bottom: false,
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
        ],
      ),
      bottomNavigationBar: AdminBottomNav(
        currentSection: _currentSection,
        onSectionChanged: _handleSectionChange,
      ),
    );
  }

  Widget _buildCurrentSection() {
    switch (_currentSection) {
      case AdminSection.dashboard:
        return DashboardSection(onSectionChanged: _handleSectionChange);

      case AdminSection.households:
        return HouseholdsSection(onSectionChanged: _handleSectionChange);

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

      case AdminSection.assistancePacks:
        return const PackManagementScreen();

      case AdminSection.finalApproval:
        return const FinalApproverScreen();

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
        return const NotificationsCenterScreen();

      case AdminSection.profile:
        return const AdminProfileSection();

      case AdminSection.purchaseApproval:
        return const PurchaseApprovalScreen();

      case AdminSection.deliveryVerification:
        return const AdminDeliveryManagementScreen();

      case AdminSection.inventoryIssues:
        return const InventoryIssuesScreen();
      case AdminSection.more:
        return AdminMoreSection(onSectionChanged: _handleSectionChange);
    }
  }
}
