import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/screens/Purchaser/widgets/procurement_card.dart';
import 'package:ration_aid/screens/Purchaser/screens/purchase_entry_screen.dart';
import 'package:ration_aid/theme/app_colors.dart';
// Removed unused FrostedPanel import

enum SortOption {
  newestFirst,
  oldestFirst,
  highestBudget,
  lowestBudget,
  nameAZ,
  nameZA,
}

class ProcurementView extends StatefulWidget {
  const ProcurementView({super.key});

  @override
  State<ProcurementView> createState() => _ProcurementViewState();
}

class _ProcurementViewState extends State<ProcurementView> {
  String _searchQuery = '';
  Timer? _debounce;
  // Removed unused _sortOption
  String _selectedStatus = 'active'; // Default: Active Tasks
  final _searchController = TextEditingController();

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

  PopupMenuItem<String> _buildFilterMenuItem(
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final isSelected = _selectedStatus == value;
    final color = isSelected
        ? AppColors.purchaserOrange
        : theme.colorScheme.onSurface;

    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isSelected
                ? AppColors.purchaserOrange
                : theme.colorScheme.onSurface.withOpacity(0.7),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            Icon(Icons.check, size: 18, color: AppColors.purchaserOrange),
          ],
        ],
      ),
    );
  }

  String _getStatusLabel(String value) {
    switch (value) {
      case 'active':
        return 'Active Tasks';
      case 'pending':
        return 'Pending';
      case 'purchased':
        return 'In Review';
      case 'rejected':
        return 'Rejected';
      default:
        return 'All';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              'Procurement Tasks',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

        // Quick Stats Dashboard (Active Focus)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.cardColor, theme.cardColor.withOpacity(0.95)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: StreamBuilder<List<ProcurementRequest>>(
              stream: ProcurementService.getPendingRequestsStream(),
              builder: (context, snapshot) {
                final requests = snapshot.data ?? [];

                // Calculate metrics (Only Actionable)
                final pendingCount = requests
                    .where((r) => r.status == ProcurementStatus.pending)
                    .length;

                final rejectedCount = requests
                    .where((r) => r.status == ProcurementStatus.rejected)
                    .length;

                final reviewCount = requests
                    .where((r) => r.status == ProcurementStatus.purchased)
                    .length;

                return Row(
                  children: [
                    _dashboardStatItem(
                      'To Buy',
                      pendingCount.toString(),
                      AppColors.purchaserOrange,
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: theme.dividerColor.withOpacity(0.5),
                    ),
                    _dashboardStatItem(
                      'In Review',
                      reviewCount.toString(),
                      Colors.blue,
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: theme.dividerColor.withOpacity(0.5),
                    ),
                    _dashboardStatItem(
                      'Rejected',
                      rejectedCount.toString(),
                      Colors.red,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Toolbar: Search | Filter
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
                      hintText: 'Search packs or areas...',
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

              // Filter Button
              Container(
                height: 46,
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedStatus == 'active'
                        ? theme.dividerColor.withOpacity(0.6)
                        : AppColors.purchaserOrange,
                  ),
                ),
                child: PopupMenuButton<String>(
                  offset: const Offset(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tooltip: 'Filter Status',
                  onSelected: (value) =>
                      setState(() => _selectedStatus = value),
                  itemBuilder: (context) => [
                    _buildFilterMenuItem(
                      'Active Tasks',
                      'active',
                      Icons.list_alt,
                    ),
                    _buildFilterMenuItem(
                      'Pending',
                      'pending',
                      Icons.pending_actions,
                    ),
                    _buildFilterMenuItem(
                      'In Review',
                      'purchased',
                      Icons.hourglass_top,
                    ),
                    _buildFilterMenuItem(
                      'Rejected',
                      'rejected',
                      Icons.cancel_outlined,
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_list_alt,
                          size: 20,
                          color: _selectedStatus == 'active'
                              ? theme.colorScheme.onSurface.withOpacity(0.7)
                              : AppColors.purchaserOrange,
                        ),
                        if (_selectedStatus != 'active') ...[
                          const SizedBox(width: 6),
                          Text(
                            _getStatusLabel(_selectedStatus),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.purchaserOrange,
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
        const SizedBox(height: 16),

        // Request List
        Expanded(
          child: StreamBuilder<List<ProcurementRequest>>(
            // Use Pending Stream (which includes Rejected & Purchased) for efficiency if possible,
            // otherwise All Stream if we needed "Verified" but we don't anymore.
            // Using getAllRequestsStream slightly safer to ensure nothing hidden by stream logic if logic changes.
            stream: ProcurementService.getAllRequestsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              var requests = snapshot.data ?? [];

              // Filter Logic
              requests = requests.where((r) {
                // Status Filter
                bool statusMatch = false;
                if (_selectedStatus == 'active') {
                  statusMatch =
                      r.status == ProcurementStatus.pending ||
                      r.status == ProcurementStatus.purchased ||
                      r.status == ProcurementStatus.rejected;
                } else if (_selectedStatus == 'pending') {
                  statusMatch = r.status == ProcurementStatus.pending;
                } else if (_selectedStatus == 'purchased') {
                  statusMatch = r.status == ProcurementStatus.purchased;
                } else if (_selectedStatus == 'rejected') {
                  statusMatch = r.status == ProcurementStatus.rejected;
                }

                // Search Filter
                bool searchMatch = true;
                if (_searchQuery.isNotEmpty) {
                  searchMatch =
                      r.packName.toLowerCase().contains(_searchQuery) ||
                      r.familyAddress.toLowerCase().contains(_searchQuery);
                }

                return statusMatch && searchMatch;
              }).toList();

              // Sort
              requests.sort(
                (a, b) => b.createdAt.compareTo(a.createdAt),
              ); // Newest first default

              if (requests.isEmpty) {
                return _buildEmptyState(context);
              }

              return RefreshIndicator(
                onRefresh: () async {
                  await Future.delayed(const Duration(milliseconds: 500));
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: requests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    return ProcurementCard(
                      request: request,
                      actionLabel: _getActionLabel(request.status),
                      onTap: () => _handleCardTap(context, request),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dashboardStatItem(String label, String value, Color color) {
    return Expanded(
      child: InkWell(
        onTap: () {
          // Auto filter on tap
          if (label == 'To Buy') setState(() => _selectedStatus = 'pending');
          if (label == 'In Review')
            setState(() => _selectedStatus = 'purchased');
          if (label == 'Rejected') setState(() => _selectedStatus = 'rejected');
        },
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.task_alt,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'All caught up!',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          Text(
            'No active tasks found.',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  String _getActionLabel(ProcurementStatus status) {
    switch (status) {
      case ProcurementStatus.pending:
        return 'Purchase Now';
      case ProcurementStatus.purchased:
        return 'View Details';
      case ProcurementStatus.rejected:
        return 'Fix & Retry';
      default:
        return 'View';
    }
  }

  void _handleCardTap(BuildContext context, ProcurementRequest request) {
    final isReadOnly =
        request.status != ProcurementStatus.pending &&
        request.status != ProcurementStatus.rejected;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PurchaseEntryScreen(request: request, isReadOnly: isReadOnly),
      ),
    );
  }
}
