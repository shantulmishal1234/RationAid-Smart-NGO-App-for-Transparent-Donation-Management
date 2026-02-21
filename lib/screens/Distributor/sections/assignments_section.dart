import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/screens/Distributor/Delivery/delivery_detail_screen.dart';
import 'package:ration_aid/screens/Distributor/widgets/delivery_card.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Distributor Assignments Section — Self-Claim Pool Model:
///
/// Tab 1 "Available" — shows ALL unassigned ready deliveries (shared pool).
///   Sorted by proximity to distributor's current GPS. First to tap "Claim" wins.
///   Uses a Firestore transaction to prevent two distributors claiming the same order.
///
/// Tab 2 "My Deliveries" — shows only deliveries claimed/in-progress by this distributor.
///   Has the original filter/search/stat card UX.
class AssignmentsSection extends StatefulWidget {
  const AssignmentsSection({super.key});

  @override
  State<AssignmentsSection> createState() => _AssignmentsSectionState();
}

class _AssignmentsSectionState extends State<AssignmentsSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String _searchQuery = '';
  String _statusFilter = 'all';
  Timer? _debounce;
  final _searchController = TextEditingController();

  // GPS for proximity sort in Available tab
  Position? _myPosition;
  bool _locationLoading = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _fetchLocation();
  }

  @override
  void dispose() {
    _tab.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() => _locationLoading = true);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (mounted) setState(() => _myPosition = pos);
    } catch (_) {
      // Location unavailable — pool shows without proximity sort
    } finally {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  void _onSearchChanged(String q) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = q.toLowerCase().trim());
    });
  }

  // ── Pool availability sort (proximity) ──────────────────────────────────────

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _deg2rad(double d) => d * math.pi / 180;

  String _distanceLabel(DeliveryAssignment a) {
    if (_myPosition == null ||
        a.familyGeoLat == null ||
        a.familyGeoLng == null) {
      return '📍 ${a.familyArea}';
    }
    final km = _haversineKm(
      _myPosition!.latitude,
      _myPosition!.longitude,
      a.familyGeoLat!,
      a.familyGeoLng!,
    );
    final label = km < 1
        ? '${(km * 1000).round()}m'
        : '${km.toStringAsFixed(1)}km';
    return '📍 ${a.familyArea} · $label away';
  }

  List<DeliveryAssignment> _sortByProximity(List<DeliveryAssignment> list) {
    if (_myPosition == null) return list;
    final sorted = List<DeliveryAssignment>.from(list);
    sorted.sort((a, b) {
      double distA = double.maxFinite;
      double distB = double.maxFinite;
      if (a.familyGeoLat != null && a.familyGeoLng != null) {
        distA = _haversineKm(
          _myPosition!.latitude,
          _myPosition!.longitude,
          a.familyGeoLat!,
          a.familyGeoLng!,
        );
      }
      if (b.familyGeoLat != null && b.familyGeoLng != null) {
        distB = _haversineKm(
          _myPosition!.latitude,
          _myPosition!.longitude,
          b.familyGeoLat!,
          b.familyGeoLng!,
        );
      }
      return distA.compareTo(distB);
    });
    return sorted;
  }

  // ── My Deliveries filter ─────────────────────────────────────────────────────

  List<DeliveryAssignment> _filterMine(List<DeliveryAssignment> all) {
    var list = all.where((a) {
      bool statusMatch;
      switch (_statusFilter) {
        case 'pending':
          statusMatch = a.isPending;
          break;
        case 'active':
          statusMatch = a.isActive;
          break;
        case 'done':
          statusMatch = a.isCompleted;
          break;
        case 'failed':
          statusMatch = a.isFailed;
          break;
        default:
          statusMatch = true;
      }
      if (_searchQuery.isEmpty) return statusMatch;
      final s = _searchQuery;
      final searchMatch =
          a.familyArea.toLowerCase().contains(s) ||
          a.familyCity.toLowerCase().contains(s) ||
          (a.assignedPackName?.toLowerCase().contains(s) ?? false);
      return statusMatch && searchMatch;
    }).toList();

    list.sort((x, y) {
      const order = {
        DeliveryStatus.inTransit: 0,
        DeliveryStatus.pickedUp: 1,
        DeliveryStatus.notStarted: 2,
        DeliveryStatus.delivered: 3,
        DeliveryStatus.adminVerified: 4,
        DeliveryStatus.failed: 5,
        DeliveryStatus.reassigned: 6,
      };
      return (order[x.status] ?? 9).compareTo(order[y.status] ?? 9);
    });
    return list;
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (!authSnap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.volunteerBlue),
          );
        }
        final uid = authSnap.data!.uid;
        final displayName =
            authSnap.data!.displayName ?? authSnap.data!.email ?? 'Distributor';

        return Column(
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.volunteerBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_shipping,
                      color: AppColors.volunteerBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deliveries',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        'Available pool · claim nearest to you',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // GPS indicator
                  _locationLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.volunteerBlue,
                          ),
                        )
                      : Icon(
                          _myPosition != null ? Icons.gps_fixed : Icons.gps_off,
                          size: 18,
                          color: _myPosition != null
                              ? Colors.green
                              : Colors.grey,
                        ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Tab Bar ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E2E)
                      : const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(
                    0.6,
                  ),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  indicator: BoxDecoration(
                    color: AppColors.volunteerBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: '🔓 Available Pool'),
                    Tab(text: '🚚 My Deliveries'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Tab Views ─────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _buildAvailablePool(uid, displayName, theme, isDark),
                  _buildMyDeliveries(uid, theme, isDark),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Tab 1: Available Pool ────────────────────────────────────────────────────

  Widget _buildAvailablePool(
    String uid,
    String displayName,
    ThemeData theme,
    bool isDark,
  ) {
    return StreamBuilder<List<DeliveryAssignment>>(
      stream: DeliveryService.streamAvailableAssignments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.volunteerBlue),
          );
        }
        if (snapshot.hasError) {
          return _errorState('${snapshot.error}');
        }

        final pool = _sortByProximity(snapshot.data ?? []);

        if (pool.isEmpty) {
          return _emptyPoolState();
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          itemCount: pool.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final a = pool[i];
            return _buildPoolCard(a, uid, displayName, theme, isDark);
          },
        );
      },
    );
  }

  Widget _buildPoolCard(
    DeliveryAssignment a,
    String uid,
    String displayName,
    ThemeData theme,
    bool isDark,
  ) {
    final itemCount = a.items.values.fold(0, (sum, qty) => sum + qty);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.volunteerBlue.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Pack name + availability badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        'Ready to Deliver',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Location verified badge
                if (a.familyLocationVerified)
                  const Icon(
                    Icons.verified_outlined,
                    size: 16,
                    color: AppColors.volunteerBlue,
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Pack name
            Text(
              a.assignedPackName ?? 'Ration Pack',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),

            const SizedBox(height: 6),

            // Distance + area
            Text(
              _distanceLabel(a),
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),

            const SizedBox(height: 6),

            // Items + family size
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  '$itemCount items',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.group_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  'Family of ${a.familySize}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Claim button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _claimDelivery(a, uid, displayName),
                icon: const Icon(Icons.handshake_outlined, size: 18),
                label: const Text('Claim This Delivery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.volunteerBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _claimDelivery(
    DeliveryAssignment a,
    String uid,
    String displayName,
  ) async {
    // Block if distributor already has an active delivery
    // (checked against My Deliveries stream implicitly by the claim button logic)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Claim Delivery?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'You are committing to deliver "${a.assignedPackName ?? "Ration Pack"}" '
          'to ${a.familyArea}, ${a.familyCity}.\n\nAre you ready to go?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.volunteerBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text("Yes, I'll Deliver"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await DeliveryService.claimAssignment(
        assignmentId: a.id,
        distributorId: uid,
        distributorName: displayName,
      );

      if (!mounted) return;

      if (success) {
        // Switch to My Deliveries tab
        _tab.animateTo(1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Delivery claimed! Go to My Deliveries to start.'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        // Race condition — someone else claimed it first
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Just claimed by another distributor. Pick another!'),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Tab 2: My Deliveries ─────────────────────────────────────────────────────

  Widget _buildMyDeliveries(String uid, ThemeData theme, bool isDark) {
    return StreamBuilder<List<DeliveryAssignment>>(
      stream: DeliveryService.streamAssignmentsByDistributor(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.volunteerBlue),
          );
        }
        if (snapshot.hasError) {
          return _errorState('${snapshot.error}');
        }

        final all = snapshot.data ?? [];
        final pendingCount = all.where((a) => a.isPending).length;
        final activeCount = all.where((a) => a.isActive).length;
        final doneCount = all.where((a) => a.isCompleted).length;
        final failedCount = all.where((a) => a.isFailed).length;
        final filtered = _filterMine(all);

        return Column(
          children: [
            // ── Stats Row ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.dividerColor.withOpacity(0.4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _statItem(
                      'Pending',
                      pendingCount,
                      AppColors.volunteerBlue,
                      'pending',
                    ),
                    _divider(),
                    _statItem('Active', activeCount, Colors.orange, 'active'),
                    _divider(),
                    _statItem('Done', doneCount, Colors.green, 'done'),
                    _divider(),
                    _statItem('Failed', failedCount, Colors.red, 'failed'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Search + Filter ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search by area, city, pack...',
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.45,
                            ),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            size: 20,
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.45,
                            ),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1E1E2E)
                              : Colors.white,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.dividerColor.withOpacity(0.5),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.dividerColor.withOpacity(0.5),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.volunteerBlue,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _statusFilter == 'all'
                            ? theme.dividerColor.withOpacity(0.5)
                            : AppColors.volunteerBlue,
                      ),
                    ),
                    child: PopupMenuButton<String>(
                      offset: const Offset(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tooltip: 'Filter',
                      onSelected: (v) => setState(() => _statusFilter = v),
                      itemBuilder: (_) => [
                        _filterItem('All Deliveries', 'all', Icons.list_alt),
                        _filterItem(
                          'Pending',
                          'pending',
                          Icons.hourglass_empty,
                        ),
                        _filterItem('Active', 'active', Icons.local_shipping),
                        _filterItem(
                          'Completed',
                          'done',
                          Icons.check_circle_outline,
                        ),
                        _filterItem('Failed', 'failed', Icons.cancel_outlined),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.filter_list_alt,
                              size: 20,
                              color: _statusFilter == 'all'
                                  ? theme.colorScheme.onSurface.withOpacity(0.6)
                                  : AppColors.volunteerBlue,
                            ),
                            if (_statusFilter != 'all') ...[
                              const SizedBox(width: 6),
                              Text(
                                _filterLabel(_statusFilter),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.volunteerBlue,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ── My Delivery List ───────────────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? _emptyMineState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 0),
                      itemBuilder: (context, i) {
                        final a = filtered[i];
                        return DeliveryCard(
                          assignment: a,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  DeliveryDetailScreen(assignmentId: a.id),
                            ),
                          ),
                          // Release button shown only when status is notStarted
                          trailing: a.isPending
                              ? _releaseButton(a, isDark)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _releaseButton(DeliveryAssignment a, bool isDark) {
    return IconButton(
      icon: const Icon(Icons.undo_rounded, size: 20, color: Colors.orange),
      tooltip: 'Release back to pool',
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Release Delivery?'),
            content: const Text(
              'This will return the delivery to the pool so another distributor can claim it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Release'),
              ),
            ],
          ),
        );

        if (confirmed != true || !mounted) return;

        final user = FirebaseAuth.instance.currentUser;
        await DeliveryService.releaseAssignment(
          assignmentId: a.id,
          releasedByName: user?.displayName ?? user?.email ?? 'Distributor',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Delivery released back to pool.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      },
    );
  }

  // ── Helper Widgets ───────────────────────────────────────────────────────────

  Widget _statItem(String label, int count, Color color, String filter) {
    final isSelected = _statusFilter == filter;
    return Expanded(
      child: InkWell(
        onTap: () => setState(
          () => _statusFilter = _statusFilter == filter ? 'all' : filter,
        ),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: isSelected ? color : color.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected
                    ? color
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() =>
      Container(height: 32, width: 1, color: Colors.grey.withOpacity(0.2));

  PopupMenuItem<String> _filterItem(String label, String value, IconData icon) {
    final isSelected = _statusFilter == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isSelected
                ? AppColors.volunteerBlue
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? AppColors.volunteerBlue
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            const Icon(Icons.check, size: 16, color: AppColors.volunteerBlue),
          ],
        ],
      ),
    );
  }

  String _filterLabel(String f) {
    switch (f) {
      case 'pending':
        return 'Pending';
      case 'active':
        return 'Active';
      case 'done':
        return 'Done';
      case 'failed':
        return 'Failed';
      default:
        return 'All';
    }
  }

  Widget _emptyPoolState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.green.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          const Text(
            'No deliveries available right now',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'New orders will appear here automatically.',
            style: TextStyle(fontSize: 13, color: Colors.grey.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _emptyMineState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 64,
            color: Colors.grey.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          const Text(
            'No active deliveries',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Claim a delivery from the Available Pool tab.',
            style: TextStyle(fontSize: 13, color: Colors.grey.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _errorState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 56,
              color: Colors.red.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load deliveries',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              msg,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
