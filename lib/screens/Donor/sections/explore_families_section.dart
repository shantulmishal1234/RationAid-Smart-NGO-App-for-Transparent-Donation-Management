import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/family_service.dart';

import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_frosted_panel.dart';

/// Explore Families Section - Browse accepted families with masked data
class ExploreFamiliesSection extends StatefulWidget {
  const ExploreFamiliesSection({super.key});

  @override
  State<ExploreFamiliesSection> createState() => _ExploreFamiliesSectionState();
}

class _ExploreFamiliesSectionState extends State<ExploreFamiliesSection> {
  final FamilyService _familyService = FamilyService();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedAssistanceType = ''; // Filter by assistance type

  // Available assistance types for filtering
  static const List<String> _assistanceTypes = [
    'Food',
    'Medicine',
    'Education',
  ];

  late Stream<List<Family>> _familiesStream;

  @override
  void initState() {
    super.initState();
    _familiesStream = _familyService.streamAcceptedFamilies();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'Explore Families',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          // Collapsible Overview Panel
          DonorFrostedPanel(
            padding: EdgeInsets.zero,
            child: StreamBuilder<List<Family>>(
              stream: _familiesStream,
              builder: (context, snapshot) {
                final families = snapshot.data ?? [];
                final totalCount = families.length;

                // Count by assistance type
                final Map<String, int> assistanceCounts = {};
                for (var type in _assistanceTypes) {
                  assistanceCounts[type] = families
                      .where((f) => f.assistanceNeeds.contains(type))
                      .length;
                }

                return ExpansionTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(
                    'Overview & Statistics',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          _statItem(
                            'Total',
                            totalCount.toString(),
                            AppColors.donorGreen,
                          ),
                          _statItem(
                            'Food',
                            assistanceCounts['Food'].toString(),
                            Colors.orange.shade700,
                          ),
                          _statItem(
                            'Medicine',
                            assistanceCounts['Medicine'].toString(),
                            Colors.red.shade600,
                          ),
                          _statItem(
                            'Education',
                            assistanceCounts['Education'].toString(),
                            Colors.blue.shade600,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Toolbar: Search | Filter
          Row(
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
                      hintText: 'Search by area...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
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
                          color: AppColors.donorGreen,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
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
                  tooltip: 'Filter by Assistance Type',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) {
                    setState(() {
                      _selectedAssistanceType = value;
                    });
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: '', child: Text('All Types')),
                    ..._assistanceTypes.map(
                      (type) => PopupMenuItem(value: type, child: Text(type)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Family list with A-Z Index
          Expanded(
            child: StreamBuilder<List<Family>>(
              stream: _familiesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                var families = List<Family>.from(snapshot.data ?? []);

                // Filter by search query
                if (_searchQuery.isNotEmpty) {
                  families = families
                      .where(
                        (f) =>
                            f.area.toLowerCase().contains(_searchQuery) ||
                            f.city.toLowerCase().contains(_searchQuery) ||
                            f.needsSummary.toLowerCase().contains(_searchQuery),
                      )
                      .toList();
                }

                // Filter by assistance type
                if (_selectedAssistanceType.isNotEmpty) {
                  families = families
                      .where(
                        (f) => f.assistanceNeeds.any(
                          (need) =>
                              need.trim().toLowerCase() ==
                              _selectedAssistanceType.trim().toLowerCase(),
                        ),
                      )
                      .toList();
                }

                // Sort alphabetically by City then Area
                families.sort((a, b) {
                  int cityCompare = a.city.toLowerCase().compareTo(
                    b.city.toLowerCase(),
                  );
                  if (cityCompare != 0) return cityCompare;
                  return a.area.toLowerCase().compareTo(b.area.toLowerCase());
                });

                if (families.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.family_restroom,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No families found matching "$_searchQuery"'
                              : 'No families available',
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: families.length,
                  itemBuilder: (context, index) {
                    return _FamilyCard(
                      family: families[index],
                      serialNumber: index + 1,
                      highlightedNeed: _selectedAssistanceType.isEmpty
                          ? null
                          : _selectedAssistanceType,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Stat item with colored dot matching admin design
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

/// Compact Family Card Widget - Efficient single-row design
class _FamilyCard extends StatelessWidget {
  final Family family;
  final int serialNumber;
  final String? highlightedNeed;

  const _FamilyCard({
    required this.family,
    required this.serialNumber,
    this.highlightedNeed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          Navigator.pushNamed(context, '/family-detail', arguments: family);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withOpacity(0.2)
                    : Colors.black.withOpacity(0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              // Serial Number
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.donorGreen.withOpacity(0.1),
                child: Text(
                  serialNumber.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.donorGreen,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Main Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Area + City (Primary - 14px bold)
                    Text(
                      '${family.area}, ${family.city}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    // Family size (Secondary - 11px)
                    Row(
                      children: [
                        Icon(
                          Icons.people,
                          size: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${family.numberOfAdults + family.numberOfChildren} members • ${family.numberOfChildren} children',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Assistance Type Badge (if available)
              // Assistance Type Badge (if available)
              if (family.assistanceNeeds.isNotEmpty) ...[
                Builder(
                  builder: (context) {
                    // Determine which need to display
                    String displayNeed = family.assistanceNeeds.first;
                    if (highlightedNeed != null) {
                      try {
                        displayNeed = family.assistanceNeeds.firstWhere(
                          (n) =>
                              n.trim().toLowerCase() ==
                              highlightedNeed!.trim().toLowerCase(),
                        );
                      } catch (_) {
                        // Keep default if match not found (unlikely due to filter)
                      }
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.donorGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.donorGreen.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        displayNeed.length > 10
                            ? '${displayNeed.substring(0, 10)}...'
                            : displayNeed,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.donorGreen,
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(width: 8),

              // Arrow icon for navigation
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
