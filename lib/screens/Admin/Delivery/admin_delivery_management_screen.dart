import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';

import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

enum DeliveryFilter { pending, active, toVerify, completed, failed }

/// Unified Admin Delivery Management Screen.
/// Uses a single-list layout with a dropdown filter instead of tabs.
class AdminDeliveryManagementScreen extends StatefulWidget {
  const AdminDeliveryManagementScreen({super.key});

  @override
  State<AdminDeliveryManagementScreen> createState() =>
      _AdminDeliveryManagementScreenState();
}

class _AdminDeliveryManagementScreenState
    extends State<AdminDeliveryManagementScreen> {
  DeliveryFilter _currentFilter = DeliveryFilter.toVerify;
  String _searchQuery = '';

  // ── Bulk Assignment State ──
  final Set<String> _selectedAssignments = {};

  // ── Shared Stream (single Firestore listener for ALL filters) ──
  late final Stream<List<DeliveryAssignment>> _assignmentsStream;

  @override
  void initState() {
    super.initState();
    _assignmentsStream = DeliveryService.streamAllAssignments()
        .asBroadcastStream();
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget currentPanel;
    bool showFab = false;

    switch (_currentFilter) {
      case DeliveryFilter.pending:
        currentPanel = _assignmentTab(
          statusFilter: (a) => a.status == DeliveryStatus.notStarted,
          emptyMsg: 'No pending deliveries',
          emptyIcon: Icons.hourglass_empty,
          isDark: isDark,
          showAssignButton: true,
        );
        showFab = _selectedAssignments.isNotEmpty;
        break;
      case DeliveryFilter.active:
        currentPanel = _assignmentTab(
          statusFilter: (a) =>
              a.status == DeliveryStatus.pickedUp ||
              a.status == DeliveryStatus.inTransit,
          emptyMsg: 'No active deliveries',
          emptyIcon: Icons.local_shipping_outlined,
          isDark: isDark,
        );
        break;
      case DeliveryFilter.toVerify:
        currentPanel = _assignmentTab(
          statusFilter: (a) =>
              a.status == DeliveryStatus.delivered && !a.adminVerified,
          emptyMsg: 'No deliveries awaiting verification',
          emptyIcon: Icons.pending_actions,
          isDark: isDark,
          showVerifyButton: true,
        );
        break;
      case DeliveryFilter.completed:
        currentPanel = _assignmentTab(
          statusFilter: (a) =>
              a.status == DeliveryStatus.delivered && a.adminVerified,
          emptyMsg: 'No completed deliveries',
          emptyIcon: Icons.verified_user,
          isDark: isDark,
        );
        break;
      case DeliveryFilter.failed:
        currentPanel = _assignmentTab(
          statusFilter: (a) =>
              a.status == DeliveryStatus.failed ||
              a.status == DeliveryStatus.reassigned,
          emptyMsg: 'No failed deliveries',
          emptyIcon: Icons.check_circle_outline,
          isDark: isDark,
          showReassignButton: true,
        );
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header/Title ──
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              'Delivery Management',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

        // ── Collapsible Overview ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FrostedPanel(
            padding: EdgeInsets.zero,
            child: StreamBuilder<List<DeliveryAssignment>>(
              stream: _assignmentsStream,
              builder: (context, snapshot) {
                final assignments = snapshot.data ?? [];
                int total = assignments.length;
                int pending = assignments
                    .where((a) => a.status == DeliveryStatus.notStarted)
                    .length;
                int toVerify = assignments
                    .where(
                      (a) =>
                          a.status == DeliveryStatus.delivered &&
                          !a.adminVerified,
                    )
                    .length;
                int completed = assignments
                    .where(
                      (a) =>
                          a.status == DeliveryStatus.delivered &&
                          a.adminVerified,
                    )
                    .length;
                int failed = assignments
                    .where(
                      (a) =>
                          a.status == DeliveryStatus.failed ||
                          a.status == DeliveryStatus.reassigned,
                    )
                    .length;

                return ExpansionTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  title: Text(
                    'Overview & Statistics',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  leading: Icon(
                    Icons.analytics_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _statItem(
                          'Total',
                          total.toString(),
                          AppColors.volunteerBlue,
                        ),
                        _statItem(
                          'Pending',
                          pending.toString(),
                          Colors.amber[700]!,
                        ),
                        _statItem(
                          'To Verify',
                          toVerify.toString(),
                          Colors.blue[600]!,
                        ),
                        _statItem(
                          'Completed',
                          completed.toString(),
                          Colors.green[600]!,
                        ),
                        _statItem(
                          'Failed',
                          failed.toString(),
                          Colors.red[400]!,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Search & Filter Row ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search deliveries...',
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
              ),
              const SizedBox(width: 12),
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PopupMenuButton<DeliveryFilter>(
                  icon: Icon(
                    Icons.filter_list,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    size: 22,
                  ),
                  tooltip: 'Filter by Status',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (val) {
                    setState(() {
                      _selectedAssignments.clear(); // Clear selections
                      _currentFilter = val;
                    });
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: DeliveryFilter.toVerify,
                      child: Text(
                        'To Verify',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    PopupMenuItem(
                      value: DeliveryFilter.pending,
                      child: Text('Pending'),
                    ),
                    PopupMenuItem(
                      value: DeliveryFilter.active,
                      child: Text('Active'),
                    ),
                    PopupMenuItem(
                      value: DeliveryFilter.completed,
                      child: Text('Completed'),
                    ),
                    PopupMenuItem(
                      value: DeliveryFilter.failed,
                      child: Text('Failed'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Main Content Area ──
        Expanded(
          child: Stack(
            children: [
              FrostedPanel(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                padding: EdgeInsets.zero,
                child: currentPanel,
              ),

              // ── Bulk Assign Floating Button ──
              if (showFab)
                Positioned(
                  bottom: 24,
                  left: 16,
                  right: 16,
                  child: ElevatedButton.icon(
                    onPressed: _showBulkAssignDialog,
                    icon: const Icon(Icons.group_add),
                    label: Text(
                      'Assign ${_selectedAssignments.length} Deliveries',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.volunteerBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                      shadowColor: AppColors.volunteerBlue.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
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

    final confirm = await showDialog<bool?>(
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
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, false),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject Proof'),
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
    if (confirm == null) return;

    try {
      if (confirm == true) {
        await DeliveryService.adminVerifyDelivery(a.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Delivery verified successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // _showRejectionReasonDialog or just direct reject
        await DeliveryService.adminRejectDelivery(a.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Delivery proof rejected.'),
              backgroundColor: Colors.red,
            ),
          );
        }
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

  Widget _statItem(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
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
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shadowColor: Colors.black12,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (onSelectChanged != null)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: onSelectChanged,
                      activeColor: AppColors.volunteerBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                if (onSelectChanged != null) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delivery to ${a.familyArea}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        a.familyCity,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _chip(a.status),
              ],
            ),

            const SizedBox(height: 8),

            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _infoChip(
                  icon: Icons.inventory_2_outlined,
                  label: a.assignedPackName ?? 'Standard Pack',
                  theme: theme,
                ),
                _infoChip(
                  icon: Icons.group_outlined,
                  label: 'Family of ${a.familySize}',
                  theme: theme,
                ),
                _infoChip(
                  icon: Icons.local_shipping_outlined,
                  label: a.assignedDistributorName ?? 'Unassigned',
                  theme: theme,
                ),
                if (a.scheduledAt != null)
                  _infoChip(
                    icon: Icons.event,
                    label: fmt.format(a.scheduledAt!),
                    theme: theme,
                  ),
              ],
            ),

            if (a.failureReason != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 14, color: Colors.red),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Failed: ${a.failureReason!.displayName}${a.failureNotes?.isNotEmpty == true ? ' - ${a.failureNotes}' : ''}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // Proof Preview
            if (a.proofPhotoUrl != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      a.proofPhotoUrl!,
                      height: 60,
                      width: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 60,
                        width: 80,
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (a.proofGeoLat != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 12,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'GPS Locked',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${a.proofGeoLat!.toStringAsFixed(4)}, ${a.proofGeoLng!.toStringAsFixed(4)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],

            if (showAssignButton || showVerifyButton || showReassignButton) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (showAssignButton)
                    TextButton.icon(
                      onPressed: onAssign,
                      icon: const Icon(Icons.person_add, size: 14),
                      label: Text(
                        a.assignedDistributorId == null ? 'Assign' : 'Reassign',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.volunteerBlue,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  if (showReassignButton)
                    TextButton.icon(
                      onPressed: onReassign,
                      icon: const Icon(Icons.swap_horiz, size: 14),
                      label: const Text(
                        'Reassign Force',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.deepOrange,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  if (showVerifyButton)
                    FilledButton.icon(
                      onPressed: onVerify,
                      icon: const Icon(Icons.verified, size: 14),
                      label: const Text(
                        'Verify',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required ThemeData theme,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
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
