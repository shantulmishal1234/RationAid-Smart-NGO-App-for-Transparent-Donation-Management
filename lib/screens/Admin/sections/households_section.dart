import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/utils/admin_queries.dart';
import 'package:ration_aid/screens/Admin/components/family_card.dart';
import 'package:ration_aid/screens/Admin/House Hold Section/add_family_screen.dart';
import 'package:ration_aid/screens/Admin/House Hold Section/family_details_screen.dart';
import 'package:ration_aid/screens/Admin/House Hold Section/edit_family_screen.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/components/admin_grf_wallet_card.dart';
import 'package:ration_aid/models/family_model.dart';

/// Households section for managing families
/// Optimized: Debounced search, cached overview stats
class HouseholdsSection extends StatefulWidget {
  final ValueChanged<AdminSection>? onSectionChanged;
  const HouseholdsSection({super.key, this.onSectionChanged});

  @override
  State<HouseholdsSection> createState() => _HouseholdsSectionState();
}

class _HouseholdsSectionState extends State<HouseholdsSection> {
  String _selectedFamilyStatus = 'all';
  String _householdSearch = '';

  // Performance: Debounce search to reduce rebuilds
  Timer? _debounce;
  final _searchController = TextEditingController();

  Future<Map<String, int>>? _statsFuture;

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  void _refreshStats() {
    setState(() {
      _statsFuture = _fetchStats();
    });
  }

  // O(1) Firestore Aggregation: Fetch stats precisely using count() to avoid
  // O(N) reads that can crash scale or spike billing.
  Future<Map<String, int>> _fetchStats() async {
    final base = FirebaseFirestore.instance
        .collection('families')
        .where('isArchived', isEqualTo: false);

    final results = await Future.wait([
      base.count().get(),
      base.where('status', isEqualTo: 'pending').count().get(),
      base.where('status', isEqualTo: 'pending_review').count().get(),
      base.where('status', isEqualTo: 'accepted').count().get(),
      base.where('status', isEqualTo: 'rejected').count().get(),
      base.where('status', isEqualTo: 'discarded').count().get(),
    ]);

    return {
      'total': results[0].count ?? 0,
      'pending': results[1].count ?? 0,
      'pendingReview': results[2].count ?? 0,
      'accepted': results[3].count ?? 0,
      'rejected': results[4].count ?? 0,
      'discarded': results[5].count ?? 0,
    };
  }

  void _onSearchChanged(String value) {
    // Cancel previous timer
    _debounce?.cancel();
    // Start new timer - only update state after 300ms of no typing
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _householdSearch = value.trim().toLowerCase();
        });
      }
    });
  }

  // Called when returning from add/edit screens to refresh data
  void _invalidateCacheAndRefresh() {
    _refreshStats();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header Row
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              'Household Management',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

        // Collapsible Overview
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),

          child: FrostedPanel(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              collapsedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Row(
                children: [
                  Text(
                    'Overview & Statistics',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _refreshStats,
                    tooltip: 'Refresh Stats',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              leading: Icon(
                Icons.analytics_outlined,
                color: theme.colorScheme.primary,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                FutureBuilder<Map<String, int>>(
                  future: _statsFuture,
                  builder: (context, snapshot) {
                    final loading =
                        snapshot.connectionState == ConnectionState.waiting;

                    if (loading) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading stats',
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }

                    final data = snapshot.data ?? {};
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _statItem(
                          'Total',
                          (data['total'] ?? 0).toString(),
                          AdminColors.primaryBlue,
                        ),
                        _statItem(
                          'Pending',
                          (data['pending'] ?? 0).toString(),
                          Colors.amber[700]!,
                        ),
                        _statItem(
                          'Review',
                          (data['pendingReview'] ?? 0).toString(),
                          Colors.deepPurple[300]!,
                        ),
                        _statItem(
                          'Accepted',
                          (data['accepted'] ?? 0).toString(),
                          Colors.green[600]!,
                        ),
                        _statItem(
                          'Rejected',
                          (data['rejected'] ?? 0).toString(),
                          Colors.red[400]!,
                        ),
                        _statItem(
                          'Discarded',
                          (data['discarded'] ?? 0).toString(),
                          Colors.grey[600]!,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // General Relief Fund Wallet Overview
        AdminGRFWalletCard(
          onManage:
              null, // To be implemented with a surplus/allocation dialog if needed
          onManageInKind: null,
        ),

        // Toolbar: Search | Filter | Add
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Search Bar
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search families...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      filled: true,
                      fillColor: theme.cardColor,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.6),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.6),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Filter Menu
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.6),
                  ),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.filter_list,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    size: 22,
                  ),
                  tooltip: 'Filter by Status',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (v) => setState(() => _selectedFamilyStatus = v),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'all',
                      child: Text('All Status'),
                    ),
                    const PopupMenuItem(
                      value: 'pending',
                      child: Text('⏳ Pending'),
                    ),
                    const PopupMenuItem(
                      value: 'pending_review',
                      child: Text('🔍 Under Review'),
                    ),
                    const PopupMenuItem(
                      value: 'accepted',
                      child: Text('✅ Accepted'),
                    ),
                    const PopupMenuItem(
                      value: 'rejected',
                      child: Text('❌ Rejected'),
                    ),
                    const PopupMenuItem(
                      value: 'discarded',
                      child: Text('🗑️ Discarded'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Add Button
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddFamilyScreen(),
                      ),
                    );
                    _invalidateCacheAndRefresh();
                  },
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Main content
        Expanded(
          child: FrostedPanel(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: EdgeInsets.zero,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: AdminQueries.familiesQuery(_selectedFamilyStatus),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load families',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  );
                }

                var docs = snapshot.data?.docs ?? [];

                // Issue #1 Fix: exclude soft-archived families from the list
                docs = docs
                    .where((d) => d.data()['isArchived'] != true)
                    .toList();

                // Sort by createdAt (oldest first)
                docs.sort((a, b) {
                  final t1 = a.data()['createdAt'] as Timestamp?;
                  final t2 = b.data()['createdAt'] as Timestamp?;
                  if (t1 == null && t2 == null) return 0;
                  if (t1 == null) return 1;
                  if (t2 == null) return -1;
                  return t1.compareTo(t2);
                });

                // Client-side search filter
                if (_householdSearch.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data();
                    final name = (data['name'] ?? '').toString().toLowerCase();
                    final cnic = (data['cnic'] ?? '').toString().toLowerCase();
                    final area = (data['area'] ?? '').toString().toLowerCase();
                    final needle = _householdSearch;
                    return name.contains(needle) ||
                        cnic.contains(needle) ||
                        area.contains(needle);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No families found.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final id = doc.id;

                    final family = Family.fromFirestore(doc);

                    return FamilyCard(
                      family: family,
                      serialNumber: index + 1,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FamilyDetailScreen(
                              familyId: id,
                              initialData: data,
                            ),
                          ),
                        );
                        setState(() {});
                      },
                      onEdit: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditFamilyScreen(familyId: id),
                          ),
                        );
                        setState(() {});
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
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
