import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/utils/admin_queries.dart';
import 'package:ration_aid/screens/Admin/utils/admin_helpers.dart';
import 'package:ration_aid/screens/Admin/utils/admin_cache.dart';
import 'package:ration_aid/screens/Admin/widgets/filters/household_status_filter.dart';
import 'package:ration_aid/screens/Admin/components/family_card.dart';
import 'package:ration_aid/screens/Admin/House Hold Section/add_family_screen.dart';
import 'package:ration_aid/screens/Admin/House Hold Section/family_details_screen.dart';
import 'package:ration_aid/screens/Admin/House Hold Section/edit_family_screen.dart';

/// Households section for managing families
/// Optimized: Debounced search, cached overview stats
class HouseholdsSection extends StatefulWidget {
  const HouseholdsSection({super.key});

  @override
  State<HouseholdsSection> createState() => _HouseholdsSectionState();
}

class _HouseholdsSectionState extends State<HouseholdsSection> {
  String _selectedFamilyStatus = 'all';
  HouseholdViewMode _householdViewMode = HouseholdViewMode.cards;
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
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Household management',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Review and support families by status, area, and assigned volunteers.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),

        const SizedBox(height: 10),

        // Right aligned controls row (view toggle + add button)
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _ViewModeSegment(
              selected: _householdViewMode,
              onChanged: (mode) {
                setState(() => _householdViewMode = mode);
              },
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddFamilyScreen()),
                );
                _invalidateCacheAndRefresh(); // Refresh with cache invalidation
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add family'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primaryBlue,
                foregroundColor: Colors.white,
                elevation: 3,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Overview panel - OPTIMIZED with cached future
        FutureBuilder<Map<String, int>>(
          future: _overviewFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 40,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            if (!snapshot.hasData) return const SizedBox.shrink();
            final d = snapshot.data!;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.95),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outline.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _overviewChip(
                    context,
                    label: 'Total',
                    value: d['total'].toString(),
                    color: AdminColors.primaryBlue,
                  ),
                  _overviewChip(
                    context,
                    label: 'Pending',
                    value: d['pending'].toString(),
                    color: Colors.amber[700]!,
                  ),
                  _overviewChip(
                    context,
                    label: 'Accepted',
                    value: d['accepted'].toString(),
                    color: Colors.green[600]!,
                  ),
                  _overviewChip(
                    context,
                    label: 'Rejected',
                    value: d['rejected'].toString(),
                    color: Colors.red[400]!,
                  ),
                  _overviewChip(
                    context,
                    label: 'Discarded',
                    value: d['discarded'].toString(),
                    color: Colors.grey[500]!,
                  ),
                ],
              ),
            );
          },
        ),

        HouseholdStatusFilter(
          selectedStatus: _selectedFamilyStatus,
          onChanged: (status) {
            setState(() {
              _selectedFamilyStatus = status;
            });
          },
        ),
        const SizedBox(height: 10),

        // Search bar
        Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: cs.outline.withOpacity(0.06)),
          ),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: theme.colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Search by name, CNIC or area...',
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
              prefixIcon: const Icon(Icons.search, size: 20),
              prefixIconColor: theme.colorScheme.onSurface.withOpacity(0.6),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
            ),
            onChanged: _onSearchChanged, // Debounced search
          ),
        ),
        const SizedBox(height: 12),

        // Main content
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.96),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
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
                    child: Text(
                      'No families found for this filter.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  );
                }

                if (_householdViewMode == HouseholdViewMode.cards) {
                  // CARD VIEW WITH EDIT
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final id = doc.id;

                      return FamilyCard(
                        id: id,
                        serialNumber: index + 1, // NEW
                        name: data['name'] ?? 'Unnamed family',
                        area: data['area'] ?? 'Unknown area',
                        address: data['address'] ?? '',
                        familySize: (data['familySize'] ?? 0) as int,
                        status: data['status'] ?? 'pending',
                        assignedVolunteerName:
                            data['assignedVolunteerName'] as String?,
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
                          setState(() {}); // refresh after edit
                        },
                      );
                    },
                  );
                } else {
                  // TABLE VIEW WITH EDIT
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 900),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 100),
                        child: Theme(
                          data: theme.copyWith(
                            dataTableTheme: DataTableThemeData(
                              headingRowColor: WidgetStateProperty.all(
                                isDark
                                    ? theme.cardColor
                                    : cs.surfaceContainerHighest,
                              ),
                              headingTextStyle: theme.textTheme.labelMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? theme.colorScheme.onSurface
                                        : cs.onSurfaceVariant,
                                  ),
                              dataTextStyle: theme.textTheme.bodySmall
                                  ?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                  ),
                              dividerThickness: 0.6,
                            ),
                          ),
                          child: DataTable(
                            columnSpacing: 18,
                            horizontalMargin: 12,
                            showBottomBorder: true,
                            columns: const [
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('Area')),
                              DataColumn(label: Text('Size')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Assigned volunteer')),
                              DataColumn(label: Text('Created')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: docs.map((doc) {
                              final data = doc.data();
                              final id = doc.id;
                              final ts = data['createdAt'] as Timestamp?;
                              final created = ts != null
                                  ? ts.toDate().toString().split('.').first
                                  : '-';
                              final assignedName =
                                  data['assignedVolunteerName'] as String?;
                              final status = (data['status'] ?? 'pending')
                                  .toString();

                              Color statusColor;
                              switch (status) {
                                case 'accepted':
                                  statusColor = Colors.green[600]!;
                                  break;
                                case 'rejected':
                                  statusColor = Colors.red[400]!;
                                  break;
                                case 'discarded':
                                  statusColor = Colors.grey[500]!;
                                  break;
                                default:
                                  statusColor = Colors.amber[700]!;
                              }

                              return DataRow(
                                cells: [
                                  DataCell(Text(data['name'] ?? 'Unnamed')),
                                  DataCell(Text(data['area'] ?? '-')),
                                  DataCell(Text('${data['familySize'] ?? 0}')),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        status,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: statusColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      assignedName ?? 'Unassigned',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: assignedName == null
                                                ? theme.colorScheme.onSurface
                                                      .withOpacity(0.5)
                                                : Colors.green,
                                          ),
                                    ),
                                  ),
                                  DataCell(Text(created)),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.7),
                                          ),
                                          tooltip: 'Edit',
                                          onPressed: () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    EditFamilyScreen(
                                                      familyId: id,
                                                    ),
                                              ),
                                            );
                                            setState(() {});
                                          },
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    FamilyDetailScreen(
                                                      familyId: id,
                                                      initialData: data,
                                                    ),
                                              ),
                                            );
                                            setState(() {});
                                          },
                                          child: const Text('Open'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  );
                }
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
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label:',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented button-like view toggle
class _ViewModeSegment extends StatelessWidget {
  final HouseholdViewMode selected;
  final ValueChanged<HouseholdViewMode> onChanged;

  const _ViewModeSegment({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip(
            context,
            mode: HouseholdViewMode.cards,
            icon: Icons.view_agenda,
            label: 'Cards',
          ),
          _chip(
            context,
            mode: HouseholdViewMode.table,
            icon: Icons.table_chart,
            label: 'Table',
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required HouseholdViewMode mode,
    required IconData icon,
    required String label,
  }) {
    final isSelected = selected == mode;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => onChanged(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primaryContainer.withOpacity(0.9)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? cs.onPrimaryContainer
                  : theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? cs.onPrimaryContainer
                    : theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
