import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/widgets/frosted_panel.dart';
// ignore: unused_import
import 'package:firebase_auth/firebase_auth.dart' as import_firebase_auth;

enum InventoryFilter { all, lowStock, highValue }

enum InventorySortOption {
  nameAZ,
  nameZA,
  stockHighLow,
  stockLowHigh,
  valueHighLow,
}

class InventoryView extends StatefulWidget {
  const InventoryView({super.key});

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  String _searchQuery = '';
  Timer? _debounce;
  InventoryFilter _selectedFilter = InventoryFilter.all;
  InventorySortOption _sortOption = InventorySortOption.nameAZ;
  final _searchController = TextEditingController();
  String? _expandedPack;
  late Stream<List<ProcurementRequest>> _inventoryStream;

  @override
  void initState() {
    super.initState();
    _inventoryStream = ProcurementService.getInventoryStream();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = query.toLowerCase();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<List<ProcurementRequest>>(
      stream: _inventoryStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final stockRequests = snapshot.data ?? [];

        // Group by Pack Name with details
        final Map<String, List<ProcurementRequest>> packGroups = {};
        for (var req in stockRequests) {
          if (!packGroups.containsKey(req.packName)) {
            packGroups[req.packName] = [];
          }
          packGroups[req.packName]!.add(req);
        }

        // Calculate pack statistics and aggregation
        int freshCount = 0;
        int reviewCount = 0;
        int urgentCount = 0;
        int lowStockCount = 0;

        final packStats = packGroups.map((name, requests) {
          final count = requests.length;
          final totalValue = requests.fold<double>(
            0,
            (sum, req) => sum + req.totalSpent,
          );
          final avgValue = count > 0 ? totalValue / count : 0;

          // Check for aging (oldest verified date)
          final oldestDate = requests
              .map((r) => r.verifiedAt ?? DateTime.now())
              .reduce((a, b) => a.isBefore(b) ? a : b);

          final daysInStock = DateTime.now().difference(oldestDate).inDays;

          if (count < 3) lowStockCount++;

          if (daysInStock > 7)
            urgentCount++;
          else if (daysInStock >= 4)
            reviewCount++;
          else
            freshCount++;

          return MapEntry(name, {
            'count': count,
            'totalValue': totalValue,
            'avgValue': avgValue,
            'oldestDate': oldestDate,
            'requests': requests,
          });
        });

        final totalValue = stockRequests.fold<double>(
          0,
          (sum, req) => sum + req.totalSpent,
        );

        // Apply filters
        var filteredPacks = Map<String, dynamic>.from(packStats);

        if (_selectedFilter == InventoryFilter.lowStock) {
          filteredPacks.removeWhere((key, value) => value['count'] >= 3);
        } else if (_selectedFilter == InventoryFilter.highValue) {
          filteredPacks.removeWhere((key, value) => value['totalValue'] < 5000);
        }

        // Apply search
        if (_searchQuery.isNotEmpty) {
          filteredPacks.removeWhere(
            (key, value) => !key.toLowerCase().contains(_searchQuery),
          );
        }

        // Sort packs
        final sortedPackNames = filteredPacks.keys.toList();
        _sortPacks(sortedPackNames, filteredPacks);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'Inventory & Stock',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // Quick Stats Dashboard (Procurement Style)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.cardColor,
                      theme.cardColor.withOpacity(0.95),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.dividerColor.withOpacity(0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Total Value / Pending Value equivalent
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Rs ${(totalValue / 1000).toStringAsFixed(1)}K',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.purchaserOrange,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total Value',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: theme.dividerColor.withOpacity(0.5),
                    ),
                    // Low Stock / Overdue equivalent
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(
                          () => _selectedFilter = InventoryFilter.lowStock,
                        ),
                        child: Column(
                          children: [
                            Text(
                              lowStockCount.toString(),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: lowStockCount > 0
                                    ? Colors.red
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Low Stock',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: theme.dividerColor.withOpacity(0.5),
                    ),
                    // Urgent Aging / Rejected equivalent
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            urgentCount.toString(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: urgentCount > 0
                                  ? Colors.red
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Aging (>7d)',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Collapsible Overview Statistics (Procurement Style)
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
                    'Inventory Overview',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                  leading: Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.purchaserOrange,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _statItem(
                          'Total Packs',
                          packStats.length.toString(),
                          AppColors.purchaserOrange,
                        ),
                        _statItem(
                          'Fresh (<4d)',
                          freshCount.toString(),
                          Colors.green[600]!,
                        ),
                        _statItem(
                          'Review (4-7d)',
                          reviewCount.toString(),
                          Colors.amber[700]!,
                        ),
                        _statItem(
                          'Urgent (>7d)',
                          urgentCount.toString(),
                          Colors.red[400]!,
                        ),
                        _statItem(
                          'Value',
                          'Rs ${(totalValue / 1000).toStringAsFixed(1)}K', // Fixed rounding
                          Colors.blue[600]!,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            const SizedBox(height: 16),

            // Smart Toolbar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Search Bar
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search packs...',
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
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                          ),
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
                              color: AppColors.purchaserOrange,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Smart Filter Button
                  Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedFilter == InventoryFilter.all
                            ? theme.dividerColor.withOpacity(0.6)
                            : AppColors.purchaserOrange,
                      ),
                    ),
                    child: PopupMenuButton<InventoryFilter>(
                      offset: const Offset(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tooltip: 'Filter Stock',
                      onSelected: (value) =>
                          setState(() => _selectedFilter = value),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: InventoryFilter.all,
                          child: Text('All Packs'),
                        ),
                        const PopupMenuItem(
                          value: InventoryFilter.lowStock,
                          child: Text('Low Stock (< 3)'),
                        ),
                        const PopupMenuItem(
                          value: InventoryFilter.highValue,
                          child: Text('High Value (> 5k)'),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(
                          _selectedFilter == InventoryFilter.all
                              ? Icons.filter_list
                              : Icons.filter_list_alt,
                          size: 20,
                          color: _selectedFilter == InventoryFilter.all
                              ? theme.colorScheme.onSurface.withOpacity(0.7)
                              : AppColors.purchaserOrange,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Sort Button
                  Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.6),
                      ),
                    ),
                    child: PopupMenuButton<InventorySortOption>(
                      icon: Icon(
                        Icons.sort,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        size: 20,
                      ),
                      tooltip: 'Sort Items',
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (value) =>
                          setState(() => _sortOption = value),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: InventorySortOption.nameAZ,
                          child: Text('Name (A-Z)'),
                        ),
                        const PopupMenuItem(
                          value: InventorySortOption.nameZA,
                          child: Text('Name (Z-A)'),
                        ),
                        const PopupMenuItem(
                          value: InventorySortOption.stockHighLow,
                          child: Text('Stock (High-Low)'),
                        ),
                        const PopupMenuItem(
                          value: InventorySortOption.stockLowHigh,
                          child: Text('Stock (Low-High)'),
                        ),
                        const PopupMenuItem(
                          value: InventorySortOption.valueHighLow,
                          child: Text('Value (High-Low)'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Result count
            if (filteredPacks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Showing ${filteredPacks.length} of ${packStats.length} pack types',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            const SizedBox(height: 8),

            // Main List
            Expanded(
              child: FrostedPanel(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                padding: EdgeInsets.zero,
                child: filteredPacks.isEmpty
                    ? _buildEmptyState(context)
                    : RefreshIndicator(
                        onRefresh: () async {
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                          itemCount: sortedPackNames.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final packName = sortedPackNames[index];
                            final packData = filteredPacks[packName];
                            final count = packData['count'] as int;
                            final totalValue = packData['totalValue'] as double;
                            final requests = (packData['requests'] as List)
                                .cast<ProcurementRequest>();
                            final isLowStock = count < 3;
                            final isExpanded = _expandedPack == packName;

                            return _buildExpandablePackCard(
                              context,
                              packName,
                              count,
                              totalValue,
                              requests,
                              isLowStock,
                              isExpanded,
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildExpandablePackCard(
    BuildContext context,
    String packName,
    int count,
    double totalValue,
    List<ProcurementRequest> requests,
    bool isLowStock,
    bool isExpanded,
  ) {
    final theme = Theme.of(context);

    if (requests.isEmpty) return const SizedBox.shrink();

    // Determine Aging Status
    // Find the oldest verified date to determine stock freshness
    final oldestDate = requests
        .map((r) => r.verifiedAt ?? DateTime.now())
        .reduce((a, b) => a.isBefore(b) ? a : b);

    final daysInStock = DateTime.now().difference(oldestDate).inDays;

    // Aging Logic: < 4 Fresh, 4-7 Review, > 7 Urgent
    Color ageColor;
    String ageLabel;
    if (daysInStock > 7) {
      ageColor = Colors.red;
      ageLabel = 'Urgent';
    } else if (daysInStock >= 4) {
      ageColor = Colors.orange;
      ageLabel = 'Review';
    } else {
      ageColor = Colors.green;
      ageLabel = 'Fresh';
    }

    // Check if verified (assuming if has verifiedAt it's verified)
    final isVerified = requests.any(
      (r) => r.status == ProcurementStatus.verified,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLowStock
              ? Colors.orange.withOpacity(0.5)
              : theme.dividerColor.withOpacity(0.5),
          width: isLowStock ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _expandedPack = isExpanded ? null : packName;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              // HEADER ROW
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Icon Container
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: ageColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: ageColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title & Badges
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  packName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isVerified) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified,
                                  size: 16,
                                  color: Colors.green, // Changed to Green
                                ),
                              ],
                              const SizedBox(width: 8),
                              // Stock Count Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isLowStock
                                      ? Colors.orange.withOpacity(0.1)
                                      : theme.dividerColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isLowStock
                                        ? Colors.orange.withOpacity(0.3)
                                        : theme.dividerColor.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  '$count In Stock',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isLowStock
                                        ? Colors.orange[800]
                                        : theme.colorScheme.onSurface
                                              .withOpacity(0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Info Row: Age • Value
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: ageColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$ageLabel (${daysInStock}d)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '•   Rs ${totalValue.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Expand Icon
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ],
                ),
              ),

              // EXPANDED DETAILS
              if (isExpanded) ...[
                Divider(height: 1, color: theme.dividerColor.withOpacity(0.5)),
                Container(
                  width: double.infinity,
                  color: theme.colorScheme.surface.withOpacity(
                    0.5,
                  ), // Subtle background
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Pack Details',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.8,
                              ),
                            ),
                          ),
                          // Compact Report Button
                          SizedBox(
                            height: 32,
                            child: OutlinedButton.icon(
                              onPressed: () => _showReportIssueDialog(
                                context,
                                packName,
                                requests,
                              ),
                              icon: Icon(
                                Icons.report_problem_outlined,
                                size: 14,
                                color: theme.colorScheme.error,
                              ),
                              label: Text(
                                'Report Issue',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                side: BorderSide(
                                  color: theme.colorScheme.error.withOpacity(
                                    0.5,
                                  ),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Detailed Stats Grid
                      Row(
                        children: [
                          Expanded(
                            child: _detailBox(
                              context,
                              'Avg Cost',
                              'Rs ${(totalValue / count).toStringAsFixed(0)}',
                              Icons.attach_money,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _detailBox(
                              context,
                              'Items',
                              '${requests.first.items.length}',
                              Icons.list,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _detailBox(
                              context,
                              'Status',
                              isLowStock ? 'Low' : 'OK',
                              isLowStock
                                  ? Icons.warning_amber
                                  : Icons.check_circle_outline,
                              color: isLowStock ? Colors.orange : Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      const Text(
                        'Items Included:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Items List (Enhanced Style)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: requests.first.items
                            .map(
                              (item) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: theme.dividerColor.withOpacity(0.2),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.02),
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '${item.name} (${item.quantity})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.8),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailBox(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    final finalColor = color ?? theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: finalColor.withOpacity(0.7)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: finalColor,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportIssueDialog(
    BuildContext context,
    String packName,
    List<ProcurementRequest> requests,
  ) {
    if (requests.isEmpty) return;

    // Filter only eligible requests (verified/stocked/issue_reported)
    final eligibleRequests = requests
        .where(
          (r) =>
              r.status == ProcurementStatus.verified ||
              r.status == ProcurementStatus.issue_reported,
        )
        .toList();

    if (eligibleRequests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No verified stock available to report issues on.'),
        ),
      );
      return;
    }

    // Sort by date (newest first)
    eligibleRequests.sort(
      (a, b) => (b.verifiedAt ?? DateTime.now()).compareTo(
        a.verifiedAt ?? DateTime.now(),
      ),
    );

    // Use the first eligible request for now
    final targetRequest = eligibleRequests.first;

    final reasonController = TextEditingController();
    String issueType = 'Damaged'; // Default
    final issueTypes = [
      'Damaged',
      'Expired',
      'Missing Items',
      'Quality Issue',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.report_problem, color: Colors.orange),
              SizedBox(width: 8),
              Text('Report Issue'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reporting issue for: $packName',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Batch Date: ${targetRequest.verifiedAt != null ? targetRequest.verifiedAt.toString().split(' ')[0] : 'N/A'}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: issueType,
                decoration: InputDecoration(
                  labelText: 'Issue Type',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: issueTypes
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (val) => setState(() => issueType = val!),
              ),
              SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Description / Reason',
                  hintText: 'Describe the issue...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please provide a reason')),
                  );
                  return;
                }

                try {
                  Navigator.pop(context); // Close dialog
                  // Show loading
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Reporting issue...')));

                  final user =
                      import_firebase_auth.FirebaseAuth.instance.currentUser;

                  await ProcurementService.reportIssue(
                    requestId: targetRequest.id,
                    issueType: issueType,
                    reason: reasonController.text.trim(),
                    reportedBy: user?.displayName ?? 'Purchaser',
                    packName: packName,
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Issue reported successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: Text('Submit Report'),
            ),
          ],
        ),
      ),
    );
  }

  void _sortPacks(List<String> packNames, Map<String, dynamic> packStats) {
    switch (_sortOption) {
      case InventorySortOption.nameAZ:
        packNames.sort();
        break;
      case InventorySortOption.nameZA:
        packNames.sort((a, b) => b.compareTo(a));
        break;
      case InventorySortOption.stockHighLow:
        packNames.sort(
          (a, b) => packStats[b]['count'].compareTo(packStats[a]['count']),
        );
        break;
      case InventorySortOption.stockLowHigh:
        packNames.sort(
          (a, b) => packStats[a]['count'].compareTo(packStats[b]['count']),
        );
        break;
      case InventorySortOption.valueHighLow:
        packNames.sort(
          (a, b) =>
              packStats[b]['totalValue'].compareTo(packStats[a]['totalValue']),
        );
        break;
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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'No packs found' : 'Inventory is empty',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
