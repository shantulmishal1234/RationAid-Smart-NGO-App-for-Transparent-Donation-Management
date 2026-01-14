import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/utils/admin_queries.dart';
import 'package:ration_aid/screens/Admin/widgets/filters/hrm_role_filter.dart';
import 'package:ration_aid/screens/Admin/components/member_tile.dart';
import 'package:ration_aid/screens/Admin/HRM(members)/add_edit_member_screen.dart';
import 'package:ration_aid/screens/Admin/Reports&Analytics/hrm_report_screen.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// HRM section for managing staff members
/// Optimized: Debounced search to reduce rebuilds
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

  // Performance: Debounce search to reduce rebuilds
  Timer? _debounce;
  final _searchController = TextEditingController();

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
    final cs = theme.colorScheme;

    return Container(
      key: const ValueKey('hrm'),
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFF7FAFF), Color(0xFFF3F7FF)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered title + subtitle
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Human resource management',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Create and manage purchaser and distributor accounts, view donor accounts, assign roles and hierarchy.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Right-aligned actions row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HrmReportScreen()),
                  );
                },
                icon: const Icon(Icons.analytics_outlined, size: 18),
                label: const Text('Report'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
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
                  }
                  setState(() {});
                },
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Add member'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Role filter inside soft card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outline.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: HrmRoleFilter(
              selectedRole: widget.hrmSelectedRole,
              onChanged: widget.onRoleChanged,
            ),
          ),
          const SizedBox(height: 10),

          // Search bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(color: cs.outline.withOpacity(0.06)),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search members by name or email...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary.withOpacity(0.7),
                ),
                prefixIcon: const Icon(Icons.search, size: 20),
                prefixIconColor: AppColors.textSecondary,
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

          // Members list inside main card
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.96),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
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
                        style: TextStyle(color: Colors.red[400]),
                      ),
                    );
                  }

                  var docs = snapshot.data?.docs ?? [];

                  // Client-side search filter
                  if (_searchText.isNotEmpty) {
                    docs = docs.where((doc) {
                      final data = doc.data();
                      final name = (data['name'] ?? '')
                          .toString()
                          .toLowerCase();
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
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }

                  // Stats summary: Members, Donors, Head, Sub head
                  final totalMembers = docs.length;
                  int donorCount = 0;
                  int headCount = 0;
                  int subHeadCount = 0;

                  for (final doc in docs) {
                    final data = doc.data();
                    final roles = List<String>.from(data['roles'] ?? []);
                    if (roles.contains('donor')) donorCount++;
                    if (roles.contains('head')) headCount++;
                    if (roles.contains('sub_head')) subHeadCount++;
                  }

                  return Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _summaryChip(
                              context,
                              label: 'Members',
                              value: totalMembers.toString(),
                              color: AdminColors.primaryBlue,
                            ),
                            _summaryChip(
                              context,
                              label: 'Donors',
                              value: donorCount.toString(),
                              color: Colors.orange[600]!,
                            ),
                            _summaryChip(
                              context,
                              label: 'Head',
                              value: headCount.toString(),
                              color: Colors.deepPurple,
                            ),
                            _summaryChip(
                              context,
                              label: 'Sub head',
                              value: subHeadCount.toString(),
                              color: Colors.teal,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final data = docs[index].data();
                            final id = docs[index].id;

                            return MemberTile(
                              uid: id,
                              name: data['name'] ?? 'Unnamed',
                              email: data['email'] ?? '',
                              roles: List<String>.from(data['roles'] ?? []),
                              department: data['department'] ?? '',
                              assignedArea: data['assignedArea'] ?? '',
                              lastLoginAt: data['lastLoginAt'] as Timestamp?,
                              deliveryCount:
                                  (data['deliveryCount'] ?? 0) as int,
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
                                      backgroundColor: Colors.green[600],
                                    ),
                                  );
                                }
                                setState(() {});
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(
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
              color: AppColors.textSecondary,
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
