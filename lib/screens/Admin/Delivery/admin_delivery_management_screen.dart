import 'dart:io';

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Unified Admin Delivery Management Screen.
/// Tab 1 – Pending (not_started)
/// Tab 2 – Active (picked_up / in_transit)
/// Tab 3 – To Verify (delivered, awaiting admin)
/// Tab 4 – Failed
/// Tab 5 – Direct (families stocked by admin, no distributor — merged from old DeliveryVerificationScreen)
class AdminDeliveryManagementScreen extends StatefulWidget {
  const AdminDeliveryManagementScreen({super.key});

  @override
  State<AdminDeliveryManagementScreen> createState() =>
      _AdminDeliveryManagementScreenState();
}

class _AdminDeliveryManagementScreenState
    extends State<AdminDeliveryManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  // ----- Direct delivery state (from old DeliveryVerificationScreen) -----
  bool _isDirectProcessing = false;
  File? _directImageFile;
  final _picker = ImagePicker();

  // ── Bulk Assignment State ──
  final Set<String> _selectedAssignments = {};

  // ── Shared Stream (single Firestore listener for ALL tabs) ──
  late final Stream<List<DeliveryAssignment>> _assignmentsStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _assignmentsStream = DeliveryService.streamAllAssignments()
        .asBroadcastStream();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AdminScaffold(
      title: 'Delivery Management',
      body: Stack(
        children: [
          Column(
            children: [
              // ── Search Bar ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by area, city, distributor, or pack...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF1E1E1E)
                        : Colors.grey[100],
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val.toLowerCase().trim());
                  },
                ),
              ),
              // ── Tab bar ──────────────────────────────────────────────────────
              Container(
                color: isDark ? const Color(0xFF121212) : Colors.white,
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.volunteerBlue,
                  unselectedLabelColor: theme.colorScheme.onSurface.withValues(
                    alpha: 0.45,
                  ),
                  indicatorColor: AppColors.volunteerBlue,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  onTap: (_) => setState(
                    () => _selectedAssignments.clear(),
                  ), // Clear selection on tab switch
                  tabs: const [
                    Tab(text: 'Pending'),
                    Tab(text: 'Active'),
                    Tab(text: 'To Verify'),
                    Tab(text: 'Completed'),
                    Tab(text: 'Failed'),
                    Tab(text: 'Direct'),
                  ],
                ),
              ),

              Expanded(
                child: FrostedPanel(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  padding: EdgeInsets.zero,
                  child: TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // Tabs 1–4: from delivery_assignments collection
                      _assignmentTab(
                        statusFilter: (a) =>
                            a.status == DeliveryStatus.notStarted,
                        emptyMsg: 'No pending deliveries',
                        emptyIcon: Icons.hourglass_empty,
                        isDark: isDark,
                        showAssignButton: true,
                      ),
                      _assignmentTab(
                        statusFilter: (a) =>
                            a.status == DeliveryStatus.pickedUp ||
                            a.status == DeliveryStatus.inTransit,
                        emptyMsg: 'No active deliveries',
                        emptyIcon: Icons.local_shipping_outlined,
                        isDark: isDark,
                      ),
                      _assignmentTab(
                        statusFilter: (a) =>
                            a.status == DeliveryStatus.delivered &&
                            !a.adminVerified,
                        emptyMsg: 'No deliveries awaiting verification',
                        emptyIcon: Icons.pending_actions,
                        isDark: isDark,
                        showVerifyButton: true,
                      ),
                      _assignmentTab(
                        statusFilter: (a) =>
                            a.status == DeliveryStatus.delivered &&
                            a.adminVerified,
                        emptyMsg: 'No completed deliveries',
                        emptyIcon: Icons.verified_user,
                        isDark: isDark,
                      ),
                      _assignmentTab(
                        statusFilter: (a) =>
                            a.status == DeliveryStatus.failed ||
                            a.status == DeliveryStatus.reassigned,
                        emptyMsg: 'No failed deliveries',
                        emptyIcon: Icons.check_circle_outline,
                        isDark: isDark,
                        showReassignButton: true,
                      ),
                      // Tab 6: Direct delivery (stocked families, admin confirms directly)
                      _buildDirectTab(isDark),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Bulk Assign Floating Button ──
          if (_selectedAssignments.isNotEmpty && _tabController.index == 0)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: ElevatedButton.icon(
                onPressed: _showBulkAssignDialog,
                icon: const Icon(Icons.group_add),
                label: Text('Assign ${_selectedAssignments.length} Deliveries'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.volunteerBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  shadowColor: AppColors.volunteerBlue.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // TAB BUILDERS
  // ════════════════════════════════════════════════════════════════════════

  Widget _assignmentTab({
    required bool Function(DeliveryAssignment) statusFilter,
    required String emptyMsg,
    required IconData emptyIcon,
    required bool isDark,
    bool showAssignButton = false,
    bool showVerifyButton = false,
    bool showReassignButton = false,
  }) {
    return StreamBuilder<List<DeliveryAssignment>>(
      stream: _assignmentsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.volunteerBlue),
          );
        }
        final filtered = (snapshot.data ?? []).where((a) {
          if (!statusFilter(a)) return false;
          if (_searchQuery.isEmpty) return true;

          final query = _searchQuery.toLowerCase();
          final areaMatch = a.familyArea.toLowerCase().contains(query);
          final cityMatch = a.familyCity.toLowerCase().contains(query);
          final packMatch = (a.assignedPackName ?? '').toLowerCase().contains(
            query,
          );
          final distMatch = (a.assignedDistributorName ?? '')
              .toLowerCase()
              .contains(query);
          final idMatch = a.id.toLowerCase().contains(query);
          final familyIdMatch = a.familyId.toLowerCase().contains(query);

          return areaMatch ||
              cityMatch ||
              packMatch ||
              distMatch ||
              idMatch ||
              familyIdMatch;
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(emptyIcon, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  emptyMsg,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final a = filtered[i];
            return _AdminDeliveryCard(
              assignment: a,
              isDark: isDark,
              showAssignButton: showAssignButton,
              showVerifyButton: showVerifyButton,
              showReassignButton: showReassignButton,
              isSelected: showAssignButton
                  ? _selectedAssignments.contains(a.id)
                  : false,
              onSelectChanged: showAssignButton
                  ? (val) {
                      setState(() {
                        if (val == true) {
                          _selectedAssignments.add(a.id);
                        } else {
                          _selectedAssignments.remove(a.id);
                        }
                      });
                    }
                  : null,
              onVerify: () => _verifyDelivery(a),
              onAssign: () => _showAssignDialog(a),
              onReassign: () => _showReassignDialog(a),
            );
          },
        );
      },
    );
  }

  /// Tab 5 — Direct delivery: stocked families waiting for admin confirmation
  Widget _buildDirectTab(bool isDark) {
    return _isDirectProcessing
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppColors.volunteerBlue),
                SizedBox(height: 16),
                Text('Processing delivery confirmation…'),
              ],
            ),
          )
        : StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('families')
                .where('status', isEqualTo: 'accepted')
                .where('fulfillmentStatus', isEqualTo: 'stocked')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.volunteerBlue,
                  ),
                );
              }

              var docs = snapshot.data!.docs;
              if (_searchQuery.isNotEmpty) {
                docs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final area = (data['area'] ?? '').toString().toLowerCase();
                  final city = (data['city'] ?? '').toString().toLowerCase();
                  return area.contains(_searchQuery) ||
                      city.contains(_searchQuery);
                }).toList();
              }
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.local_shipping_outlined,
                        size: 64,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No stocked families pending direct delivery',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Families with fulfillmentStatus = stocked\nwill appear here for direct admin confirmation.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final family = Family.fromFirestore(docs[index]);
                  return _buildDirectDeliveryCard(family, isDark);
                },
              );
            },
          );
  }

  Widget _buildDirectDeliveryCard(Family family, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              color: Colors.teal,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.home_work_outlined,
                        color: Colors.teal,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${family.address}, ${family.area}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            family.city,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.teal.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Text(
                        'Stocked',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.teal,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                _infoRow(
                  context,
                  'Pack',
                  family.assignedPackName ?? 'Standard Pack',
                ),
                _infoRow(context, 'Phone', family.phone ?? 'N/A'),
                _infoRow(
                  context,
                  'Family Size',
                  '${family.familySize} members',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmDirectDelivery(family),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text(
                      'Confirm Delivery (Upload Proof)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // DIRECT DELIVERY LOGIC (merged from DeliveryVerificationScreen)
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _confirmDirectDelivery(Family family) async {
    // BUG6 FIX: Use a LOCAL variable per dialog invocation so that
    // each family dialog gets its own isolated image state.
    File? dialogImageFile;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDlgState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.verified_outlined, color: Colors.teal),
              const SizedBox(width: 8),
              const Text('Confirm Direct Delivery'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.teal, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${family.address}, ${family.area}, ${family.city}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Take or select a proof of delivery photo:',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final picked = await _picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 85,
                  );
                  if (picked != null) {
                    setDlgState(() => dialogImageFile = File(picked.path));
                  }
                },
                child: Container(
                  height: 170,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _directImageFile != null
                          ? Colors.green
                          : Colors.grey.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: dialogImageFile != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            dialogImageFile!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt,
                              size: 44,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Tap to take photo',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                ),
              ),
              if (dialogImageFile != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await _picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 85,
                    );
                    if (picked != null) {
                      setDlgState(() => dialogImageFile = File(picked.path));
                    }
                  },
                  icon: const Icon(Icons.photo_library, size: 16),
                  label: const Text('Choose from Gallery'),
                  style: TextButton.styleFrom(foregroundColor: Colors.teal),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: dialogImageFile == null
                  ? null
                  : () {
                      Navigator.pop(dialogContext);
                      _processDirectDelivery(family, dialogImageFile!);
                    },
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('Confirm Delivery'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processDirectDelivery(Family family, File proofImage) async {
    setState(() => _isDirectProcessing = true);

    try {
      // 1. Upload proof image
      final url = await CloudinaryService.uploadImage(proofImage);
      if (url == null) throw Exception('Image upload failed');

      // 2. Update family record
      await FirebaseFirestore.instance
          .collection('families')
          .doc(family.id)
          .update({
            'fulfillmentStatus': 'delivered',
            'deliveredAt': FieldValue.serverTimestamp(),
            'deliveryProof': url,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // 3. Log to audit
      await AuditService.logFamilyAction(
        action: 'Direct Delivery Confirmed (Admin)',
        familyId: family.id,
        familyName: '${family.area}, ${family.city}',
        details: 'Proof photo uploaded via Direct tab',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Direct delivery confirmed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isDirectProcessing = false);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // ASSIGNMENT ACTIONS (Tabs 1–4)
  // ════════════════════════════════════════════════════════════════════════

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  Future<void> _verifyDelivery(DeliveryAssignment a) async {
    bool hasLocationWarning = false;
    double? distanceMeters;
    bool isMissingGPS = false;

    if (a.familyGeoLat != null &&
        a.familyGeoLng != null &&
        a.proofGeoLat != null &&
        a.proofGeoLng != null) {
      distanceMeters = _haversine(
        a.familyGeoLat!,
        a.familyGeoLng!,
        a.proofGeoLat!,
        a.proofGeoLng!,
      );
      if (distanceMeters > 500) {
        hasLocationWarning = true;
      }
    } else {
      isMissingGPS = true;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            if (hasLocationWarning || isMissingGPS)
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            if (hasLocationWarning || isMissingGPS) const SizedBox(width: 8),
            const Text('Verify Delivery'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirm the proof of delivery is valid and the delivery was successful?',
            ),
            if (hasLocationWarning) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '⚠️ Warning: Proof of delivery was captured ${(distanceMeters! / 1000).toStringAsFixed(1)}km away from the family\'s registered location.',
                  style: const TextStyle(
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (isMissingGPS) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  '⚠️ Warning: This delivery lacks verifiable GPS data. Please double-check the proof photo carefully before approving.',
                  style: TextStyle(
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await DeliveryService.adminVerifyDelivery(a.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Delivery verified successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showBulkAssignDialog() async {
    if (_selectedAssignments.isEmpty) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('roles', arrayContains: 'distributor')
        .get();

    if (!mounted) return;

    if (snap.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No distributors found. Add distributors first in HRM.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final distributors = snap.docs
        .map(
          (d) => <String, String>{
            'id': d.id,
            'name':
                (d.data()['name'] ??
                        d.data()['display_name'] ??
                        d.data()['email'] ??
                        'Unknown')
                    .toString(),
          },
        )
        .toList();

    String? selectedId;
    final schedController = TextEditingController();
    final noteController = TextEditingController();
    DateTime? scheduled;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Bulk Assign ${_selectedAssignments.length} Deliveries'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  hint: const Text('Select Distributor'),
                  items: distributors
                      .map(
                        (d) => DropdownMenuItem(
                          value: d['id']!,
                          child: Text(d['name']!),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDlgState(() => selectedId = val),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: schedController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Scheduled Time (Optional)',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (d == null || !mounted) return;
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (t == null) return;
                    scheduled = DateTime(
                      d.year,
                      d.month,
                      d.day,
                      t.hour,
                      t.minute,
                    );
                    setDlgState(() {
                      schedController.text = DateFormat(
                        'MMM dd, hh:mm a',
                      ).format(scheduled!);
                    });
                  },
                ),
                if (scheduled != null)
                  TextButton.icon(
                    onPressed: () {
                      setDlgState(() {
                        scheduled = null;
                        schedController.clear();
                      });
                    },
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear Time'),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Admin Note (Optional)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      _executeBulkAssign(
                        selectedDistributorId: selectedId!,
                        distributors: distributors,
                        scheduled: scheduled,
                        note: noteController.text.trim(),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.volunteerBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Assign All'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeBulkAssign({
    required String selectedDistributorId,
    required List<Map<String, String>> distributors,
    DateTime? scheduled,
    required String note,
  }) async {
    final distName = distributors.firstWhere(
      (d) => d['id'] == selectedDistributorId,
    )['name'];

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final assignmentId in _selectedAssignments) {
        final ref = FirebaseFirestore.instance
            .collection('delivery_assignments')
            .doc(assignmentId);
        batch.update(ref, {
          'assignedDistributorId': selectedDistributorId,
          'assignedDistributorName': distName,
          'status': DeliveryStatus.notStarted.toFirestore(),
          'scheduledAt': scheduled != null
              ? Timestamp.fromDate(scheduled)
              : null,
          'adminNote': note.isEmpty ? null : note,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Write notification payload for the distributor
        final notifRef = FirebaseFirestore.instance
            .collection('notifications')
            .doc();
        batch.set(notifRef, {
          'userId': selectedDistributorId,
          'title': 'New Delivery Assigned 🚚',
          'body':
              'You have been assigned to delivery ID: ${assignmentId.substring(0, 6)}...',
          'type': 'delivery_assigned',
          'assignmentId': assignmentId,
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Successfully assigned ${_selectedAssignments.length} deliveries to $distName!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _selectedAssignments.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showAssignDialog(DeliveryAssignment a) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('roles', arrayContains: 'distributor')
        .get();

    if (!mounted) return;

    if (snap.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No distributors found. Add distributors first in HRM.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final distributors = snap.docs
        .map(
          (d) => {
            'id': d.id,
            'name':
                d.data()['name'] ??
                d.data()['display_name'] ??
                d.data()['email'] ??
                'Unknown',
          },
        )
        .toList();

    String? selectedId;
    final schedController = TextEditingController();
    final noteController = TextEditingController();
    DateTime? scheduled;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Assign Distributor'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Family: ${a.familyArea}, ${a.familyCity}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  decoration: const InputDecoration(
                    labelText: 'Select Distributor',
                    border: OutlineInputBorder(),
                  ),
                  items: distributors
                      .map(
                        (d) => DropdownMenuItem<String>(
                          value: d['id'] as String,
                          child: Text(d['name']! as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDlgState(() => selectedId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: schedController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Scheduled Date/Time (optional)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 30),
                          ),
                        );
                        if (date == null) return;
                        final time = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time == null) return;
                        scheduled = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                        setDlgState(() {
                          schedController.text = DateFormat(
                            'MMM dd, yyyy hh:mm a',
                          ).format(scheduled!);
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Admin Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedId == null
                  ? null
                  : () async {
                      final dist = distributors.firstWhere(
                        (d) => d['id'] == selectedId,
                      );
                      Navigator.pop(ctx);
                      try {
                        await FirebaseFirestore.instance
                            .collection('delivery_assignments')
                            .doc(a.id)
                            .update({
                              'assignedDistributorId': selectedId,
                              'assignedDistributorName': dist['name'],
                              'scheduledAt': scheduled != null
                                  ? Timestamp.fromDate(scheduled!)
                                  : null,
                              'adminNote': noteController.text.trim().isEmpty
                                  ? null
                                  : noteController.text.trim(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });

                        // Firestore notification record
                        await FirebaseFirestore.instance
                            .collection('notifications')
                            .add({
                              'userId': selectedId,
                              'title': 'New Delivery Assigned 🚚',
                              'body':
                                  'You have a delivery to ${a.familyArea}, ${a.familyCity}. Tap to view.',
                              'type': 'delivery_assigned',
                              'assignmentId': a.id,
                              'createdAt': FieldValue.serverTimestamp(),
                              'read': false,
                            });

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Distributor assigned!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.volunteerBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );

    schedController.dispose();
    noteController.dispose();
  }

  Future<void> _showReassignDialog(DeliveryAssignment a) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('roles', arrayContains: 'distributor')
        .get();

    if (!mounted) return;

    final distributors = snap.docs
        .map(
          (d) => {
            'id': d.id,
            'name': d.data()['name'] ?? d.data()['email'] ?? 'Unknown',
          },
        )
        .toList();

    String? selectedId;
    final noteController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Reassign Delivery'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedId,
                decoration: const InputDecoration(
                  labelText: 'Select New Distributor',
                  border: OutlineInputBorder(),
                ),
                items: distributors
                    .map(
                      (d) => DropdownMenuItem<String>(
                        value: d['id'] as String,
                        child: Text(d['name']! as String),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setDlgState(() => selectedId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for Reassignment',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _releaseToPool(a);
                  },
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Release to Available Pool'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                    side: BorderSide(
                      color: Colors.deepOrange.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedId == null
                  ? null
                  : () async {
                      final dist = distributors.firstWhere(
                        (d) => d['id'] == selectedId,
                      );
                      Navigator.pop(ctx);
                      try {
                        await DeliveryService.reassignDelivery(
                          assignmentId: a.id,
                          newDistributorId: selectedId!,
                          newDistributorName: dist['name']! as String,
                          adminNote: noteController.text.trim(),
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Delivery reassigned!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reassign'),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
  }

  Future<void> _releaseToPool(DeliveryAssignment a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release to Pool'),
        content: const Text(
          'This will remove the current distributor and make the delivery available for anyone in the Available Pool. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Release'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await DeliveryService.releaseAssignment(
        assignmentId: a.id,
        releasedByName: 'Admin',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Delivery released to pool!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // SHARED HELPERS
  // ════════════════════════════════════════════════════════════════════════

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// DELIVERY ASSIGNMENT CARD (for tabs 1–4)
// ════════════════════════════════════════════════════════════════════════════

class _AdminDeliveryCard extends StatelessWidget {
  final DeliveryAssignment assignment;
  final bool isDark;
  final bool showAssignButton;
  final bool showVerifyButton;
  final bool showReassignButton;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectChanged;
  final VoidCallback onVerify;
  final VoidCallback onAssign;
  final VoidCallback onReassign;

  const _AdminDeliveryCard({
    required this.assignment,
    required this.isDark,
    this.showAssignButton = false,
    this.showVerifyButton = false,
    this.showReassignButton = false,
    this.isSelected = false,
    this.onSelectChanged,
    required this.onVerify,
    required this.onAssign,
    required this.onReassign,
  });

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final fmt = DateFormat('MMM dd, hh:mm a');

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: _statusColor(a.status),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (onSelectChanged != null)
                      Checkbox(
                        value: isSelected,
                        onChanged: onSelectChanged,
                        activeColor: AppColors.volunteerBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        '${a.familyArea}, ${a.familyCity}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    _chip(a.status),
                  ],
                ),
                const SizedBox(height: 8),
                _row(
                  context,
                  'Distributor',
                  a.assignedDistributorName ?? 'Unassigned',
                ),
                _row(context, 'Pack', a.assignedPackName ?? 'Standard Pack'),
                _row(
                  context,
                  'Items',
                  '${a.items.length} types · Family of ${a.familySize}',
                ),
                if (a.scheduledAt != null)
                  _row(context, 'Scheduled', fmt.format(a.scheduledAt!)),
                if (a.failureReason != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Failure: ${a.failureReason!.displayName}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  if (a.failureNotes?.isNotEmpty == true)
                    Text(
                      a.failureNotes!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                ],

                // Proof Preview
                if (a.proofPhotoUrl != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      a.proofPhotoUrl!,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 80,
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  if (a.proofGeoLat != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.gps_fixed,
                            size: 12,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${a.proofGeoLat!.toStringAsFixed(5)}, ${a.proofGeoLng!.toStringAsFixed(5)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],

                if (showAssignButton ||
                    showVerifyButton ||
                    showReassignButton) ...[
                  const SizedBox(height: 12),
                  if (showAssignButton)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onAssign,
                        icon: const Icon(Icons.person_add, size: 16),
                        label: Text(
                          a.assignedDistributorId == null
                              ? 'Assign Distributor'
                              : 'Reassign Distributor',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.volunteerBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  if (showVerifyButton)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onVerify,
                        icon: const Icon(Icons.verified, size: 16),
                        label: const Text(
                          'Verify Delivery',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  if (showReassignButton)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onReassign,
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text(
                          'Reassign Delivery',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(DeliveryStatus s) {
    final color = _statusColor(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        s.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Color _statusColor(DeliveryStatus s) {
    switch (s) {
      case DeliveryStatus.notStarted:
        return Colors.grey;
      case DeliveryStatus.pickedUp:
        return Colors.orange;
      case DeliveryStatus.inTransit:
        return AppColors.volunteerBlue;
      case DeliveryStatus.delivered:
        return Colors.purple;
      case DeliveryStatus.adminVerified:
        return Colors.green;
      case DeliveryStatus.failed:
        return Colors.red;
      case DeliveryStatus.reassigned:
        return Colors.deepOrange;
    }
  }
}
