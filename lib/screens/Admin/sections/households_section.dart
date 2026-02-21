import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/utils/admin_queries.dart';
import 'package:ration_aid/screens/Admin/utils/admin_helpers.dart';
import 'package:ration_aid/screens/Admin/utils/admin_cache.dart';
import 'package:ration_aid/screens/Admin/components/family_card.dart';
import 'package:ration_aid/screens/Admin/House Hold Section/add_family_screen.dart';
import 'package:ration_aid/screens/Admin/House Hold Section/family_details_screen.dart';
import 'package:ration_aid/screens/Admin/House Hold Section/edit_family_screen.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';

/// Households section for managing families
/// Optimized: Debounced search, cached overview stats
class HouseholdsSection extends StatefulWidget {
  const HouseholdsSection({super.key});

  @override
  State<HouseholdsSection> createState() => _HouseholdsSectionState();
}

class _HouseholdsSectionState extends State<HouseholdsSection> {
  String _selectedFamilyStatus = 'all';
  String _householdSearch = '';

  // Performance: Debounce search to reduce rebuilds
  Timer? _debounce;
  final _searchController = TextEditingController();

  // Cache overview future
  late Future<Map<String, int>> _overviewFuture;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  void _loadOverview({bool forceRefresh = false}) {
    _overviewFuture = AdminHelpers.loadHouseholdOverview(
      forceRefresh: forceRefresh,
    );
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

  void _invalidateCacheAndRefresh() {
    AdminCache.invalidate(CacheKeys.householdOverview);
    _loadOverview(forceRefresh: true);
    setState(() {});
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
              title: Text(
                'Overview & Statistics',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
              leading: Icon(
                Icons.analytics_outlined,
                color: theme.colorScheme.primary,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                FutureBuilder<Map<String, int>>(
                  future: _overviewFuture,
                  builder: (context, snapshot) {
                    final d =
                        snapshot.data ??
                        {
                          'total': 0,
                          'pending': 0,
                          'accepted': 0,
                          'rejected': 0,
                          'discarded': 0,
                        };
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

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _statItem(
                          'Total',
                          d['total'].toString(),
                          AdminColors.primaryBlue,
                        ),
                        _statItem(
                          'Pending',
                          d['pending'].toString(),
                          Colors.amber[700]!,
                        ),
                        _statItem(
                          'Accepted',
                          d['accepted'].toString(),
                          Colors.green[600]!,
                        ),
                        _statItem(
                          'Rejected',
                          d['rejected'].toString(),
                          Colors.red[400]!,
                        ),
                        _statItem(
                          'Discarded',
                          d['discarded'].toString(),
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
        const SizedBox(height: 16),

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
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      filled: true,
                      fillColor: theme.cardColor,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withOpacity(0.6),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withOpacity(0.6),
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
                    color: theme.dividerColor.withOpacity(0.6),
                  ),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.filter_list,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
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
                      value: 'accepted',
                      child: Text('Accepted'),
                    ),
                    const PopupMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                    const PopupMenuItem(
                      value: 'discarded',
                      child: Text('Discarded'),
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
                          color: theme.colorScheme.onSurface.withOpacity(0.2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No families found.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
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

                    return FamilyCard(
                      id: id,
                      serialNumber: index + 1,
                      name: data['name'] ?? 'Unnamed family',
                      area: data['area'] ?? 'Unknown area',
                      address: data['address'] ?? '',
                      familySize: (data['familySize'] ?? 0) as int,
                      status: data['status'] ?? 'pending',
                      assignedVolunteerName:
                          data['assignedVolunteerName'] as String?,
                      targetAmount: (data['targetAmount'] ?? 0).toDouble(),
                      raisedAmount: (data['raisedAmount'] ?? 0).toDouble(),
                      surplusAmount: (data['surplusAmount'] ?? 0).toDouble(),
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
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
