import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/utils/admin_queries.dart';
import 'package:ration_aid/screens/Admin/utils/admin_helpers.dart';
import 'package:ration_aid/screens/Admin/utils/admin_cache.dart';
import 'package:ration_aid/screens/Admin/components/member_tile.dart';
import 'package:ration_aid/screens/Admin/HRM(members)/add_edit_member_screen.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';

/// HRM section for managing staff members
class HrmSection extends StatefulWidget {
  final String hrmSelectedRole;
  final ValueChanged<String> onRoleChanged;

  const HrmSection({
    super.key,
    required this.hrmSelectedRole,
    required this.onRoleChanged,
  });

  @override
  State<HrmSection> createState() => _HrmSectionState();
}

class _HrmSectionState extends State<HrmSection> {
  String _searchText = '';
  late Future<Map<String, int>> _overviewFuture;

  // Performance: Debounce search to reduce rebuilds
  Timer? _debounce;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  void _loadOverview({bool forceRefresh = false}) {
    _overviewFuture = AdminHelpers.loadHrmOverview(forceRefresh: forceRefresh);
  }

  void _invalidateCacheAndRefresh() {
    AdminCache.invalidate(CacheKeys.hrmOverview);
    _loadOverview(forceRefresh: true);
    setState(() {});
  }

  void _onSearchChanged(String value) {
    // Cancel previous timer
    _debounce?.cancel();
    // Start new timer - only update state after 300ms of no typing
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchText = value.trim().toLowerCase();
        });
      }
    });
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
              'Human Resource Management',
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
                          'purchaser': 0,
                          'distributor': 0,
                          'donor': 0,
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
                        _overviewChip(
                          context,
                          label: 'Total',
                          value: d['total'].toString(),
                          color: AdminColors.primaryBlue,
                        ),
                        _overviewChip(
                          context,
                          label: 'Purchaser',
                          value: d['purchaser'].toString(),
                          color: Colors.purple[600]!,
                        ),
                        _overviewChip(
                          context,
                          label: 'Distributor',
                          value: d['distributor'].toString(),
                          color: Colors.teal[600]!,
                        ),
                        _overviewChip(
                          context,
                          label: 'Donor',
                          value: d['donor'].toString(),
                          color: Colors.orange[600]!,
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
                      hintText: 'Search members...',
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
                  tooltip: 'Filter by Role',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: widget.onRoleChanged,
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'all', child: Text('All Roles')),
                    const PopupMenuItem(value: 'admin', child: Text('Admin')),
                    const PopupMenuItem(
                      value: 'purchaser',
                      child: Text('Purchaser'),
                    ),
                    const PopupMenuItem(
                      value: 'distributor',
                      child: Text('Distributor'),
                    ),
                    const PopupMenuItem(value: 'donor', child: Text('Donor')),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Add Button
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddOrEditMemberScreen(),
                      ),
                    );

                    if (!mounted) return;
                    if (result != null && result.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result),
                          backgroundColor: Colors.green[600],
                        ),
                      );
                      _invalidateCacheAndRefresh();
                    }
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

        // Members list inside main card
        Expanded(
          child: FrostedPanel(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: EdgeInsets.zero,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: AdminQueries.hrmUsersQuery(widget.hrmSelectedRole),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load members',
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
                if (_searchText.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data();
                    final name = (data['name'] ?? '').toString().toLowerCase();
                    final email = (data['email'] ?? '')
                        .toString()
                        .toLowerCase();
                    final needle = _searchText;
                    return name.contains(needle) || email.contains(needle);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No members found for this filter.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final id = docs[index].id;

                    return MemberTile(
                      uid: id,
                      serialNumber: index + 1,
                      name: data['name'] ?? 'Unnamed',
                      email: data['email'] ?? '',
                      roles: List<String>.from(data['roles'] ?? []),
                      department: data['department'] ?? '',
                      assignedArea: data['assignedArea'] ?? '',
                      lastLoginAt: data['lastLoginAt'] as Timestamp?,
                      deliveryCount: (data['deliveryCount'] ?? 0) as int,
                      onTap: () async {
                        final result = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddOrEditMemberScreen(
                              uid: id,
                              initialData: data,
                            ),
                          ),
                        );

                        if (!mounted) return;
                        if (result != null && result.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _invalidateCacheAndRefresh();
                        }
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

  Widget _overviewChip(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
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
