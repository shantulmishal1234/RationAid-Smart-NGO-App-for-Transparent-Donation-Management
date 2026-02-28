import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/screens/Distributor/widgets/delivery_card.dart';
import 'package:ration_aid/screens/Distributor/Delivery/delivery_detail_screen.dart';
import 'package:ration_aid/theme/app_colors.dart';

class DistributorHistorySection extends StatefulWidget {
  final bool isSupervisor;
  const DistributorHistorySection({super.key, required this.isSupervisor});

  @override
  State<DistributorHistorySection> createState() =>
      _DistributorHistorySectionState();
}

class _DistributorHistorySectionState extends State<DistributorHistorySection> {
  String _filterStatus = 'All'; // All, Active, Completed, Failed

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  // Date state
  DateTimeRange? _selectedDateRange;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = query.toLowerCase();
        });
      }
    });
  }

  Future<void> _showCustomRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.volunteerBlue,
              onPrimary: Colors.white,
              surface: Theme.of(context).cardColor,
              onSurface: Theme.of(context).textTheme.bodyLarge!.color!,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Please log in'));
    }

    return StreamBuilder<List<DeliveryAssignment>>(
      stream: DeliveryService.getSmartHistoryStream(
        user.uid,
        widget.isSupervisor,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.volunteerBlue),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Could not load history',
              style: TextStyle(color: Colors.red[400]),
            ),
          );
        }

        final allAssignments = snapshot.data ?? [];

        // 1. Stats Calculation (Before Filters)
        final totalCountAllTime = allAssignments.length;
        final completedCountAllTime = allAssignments
            .where((a) => a.isCompleted)
            .length;
        final failedCountAllTime = allAssignments
            .where((a) => a.isFailed)
            .length;
        final familiesHelped = allAssignments
            .where((a) => a.isCompleted)
            .fold<int>(0, (sum, a) => sum + a.familySize);

        // 2. Apply Filters
        var filteredAssignments = List<DeliveryAssignment>.from(allAssignments);

        if (_filterStatus != 'All') {
          filteredAssignments = filteredAssignments.where((a) {
            if (_filterStatus == 'Active') return a.isActive || a.isPending;
            if (_filterStatus == 'Completed') return a.isCompleted;
            if (_filterStatus == 'Failed') return a.isFailed;
            return true;
          }).toList();
        }

        // 3. Apply Date Filter
        if (_selectedDateRange != null) {
          filteredAssignments = filteredAssignments.where((a) {
            final dateToCheck = a.deliveredAt ?? a.failedAt ?? a.createdAt;
            return dateToCheck.isAfter(
                  _selectedDateRange!.start.subtract(
                    const Duration(seconds: 1),
                  ),
                ) &&
                dateToCheck.isBefore(
                  _selectedDateRange!.end.add(const Duration(days: 1)),
                );
          }).toList();
        }

        // 4. Apply Search
        if (_searchQuery.isNotEmpty) {
          filteredAssignments = filteredAssignments.where((a) {
            return (a.familyArea.toLowerCase().contains(_searchQuery)) ||
                (a.familyCity.toLowerCase().contains(_searchQuery)) ||
                (a.assignedPackName?.toLowerCase().contains(_searchQuery) ??
                    false);
          }).toList();
        }

        // Sort by date desc (newest first)
        filteredAssignments.sort((a, b) {
          final dateA = a.deliveredAt ?? a.failedAt ?? a.createdAt;
          final dateB = b.deliveredAt ?? b.failedAt ?? b.createdAt;
          return dateB.compareTo(dateA);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Header ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'Delivery History',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // --- Quick Stats Dashboard (Purchaser Style) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.cardColor,
                      theme.cardColor.withValues(alpha: 0.95),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Total Deliveries
                    Expanded(
                      child: _buildStatItem(
                        theme,
                        totalCountAllTime.toString(),
                        'Total',
                        AppColors.volunteerBlue,
                      ),
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: theme.dividerColor.withValues(alpha: 0.5),
                    ),
                    // Completed
                    Expanded(
                      child: _buildStatItem(
                        theme,
                        completedCountAllTime.toString(),
                        'Completed',
                        Colors.green,
                      ),
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: theme.dividerColor.withValues(alpha: 0.5),
                    ),
                    // Families Helped
                    Expanded(
                      child: _buildStatItem(
                        theme,
                        familiesHelped.toString(),
                        'People Fed',
                        Colors.orange,
                      ),
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: theme.dividerColor.withValues(alpha: 0.5),
                    ),
                    // Failed
                    Expanded(
                      child: _buildStatItem(
                        theme,
                        failedCountAllTime.toString(),
                        'Failed',
                        Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // --- Smart Toolbar (Search + Filters) ---
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
                          hintText: 'Search history...',
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
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.dividerColor.withValues(alpha: 0.5),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.dividerColor.withValues(alpha: 0.5),
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

                  // Date Filter Button
                  _buildToolbarButton(
                    theme,
                    icon: Icons.calendar_today_outlined,
                    isActive: _selectedDateRange != null,
                    tooltip: 'Filter by Date',
                    onTap: _showCustomRangePicker,
                  ),

                  const SizedBox(width: 8),

                  // Status Filter Dropdown
                  Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _filterStatus != 'All'
                            ? AppColors.volunteerBlue
                            : theme.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: PopupMenuButton<String>(
                      tooltip: 'Filter by Status',
                      offset: const Offset(0, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      icon: Icon(
                        Icons.filter_list_rounded,
                        color: _filterStatus != 'All'
                            ? AppColors.volunteerBlue
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                        size: 22,
                      ),
                      onSelected: (value) =>
                          setState(() => _filterStatus = value),
                      itemBuilder: (context) => [
                        _buildPopupItem(context, 'All', Icons.all_inclusive),
                        _buildPopupItem(
                          context,
                          'Active',
                          Icons.local_shipping,
                        ),
                        _buildPopupItem(
                          context,
                          'Completed',
                          Icons.check_circle_outline,
                        ),
                        _buildPopupItem(
                          context,
                          'Failed',
                          Icons.cancel_outlined,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Active Filters Row
            if (_selectedDateRange != null || _filterStatus != 'All')
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 12, right: 16),
                child: Row(
                  children: [
                    if (_filterStatus != 'All')
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildActiveChip(
                          theme,
                          'Status: $_filterStatus',
                          () => setState(() => _filterStatus = 'All'),
                        ),
                      ),
                    if (_selectedDateRange != null)
                      _buildActiveChip(
                        theme,
                        '${DateFormat('MMM d').format(_selectedDateRange!.start)} - ${DateFormat('MMM d').format(_selectedDateRange!.end)}',
                        () => setState(() => _selectedDateRange = null),
                      ),
                    const Spacer(),
                    if (filteredAssignments.isNotEmpty)
                      Text(
                        '${filteredAssignments.length} found',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),

            // --- List View ---
            Expanded(
              child: filteredAssignments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history_toggle_off,
                            size: 64,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty ||
                                    _filterStatus != 'All' ||
                                    _selectedDateRange != null
                                ? 'No results found for your filters.'
                                : 'No history available.',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                        top: 16,
                        left: 16,
                        right: 16,
                        bottom: 120, // Space for bottom nav
                      ),
                      itemCount: filteredAssignments.length,
                      itemBuilder: (context, index) {
                        return DeliveryCard(
                          assignment: filteredAssignments[index],
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DeliveryDetailScreen(
                                  assignmentId: filteredAssignments[index].id,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // --- Helper Widgets ---

  Widget _buildStatItem(
    ThemeData theme,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbarButton(
    ThemeData theme, {
    required IconData icon,
    required bool isActive,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 46,
      width: 46,
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.volunteerBlue.withValues(alpha: 0.1)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.volunteerBlue
              : theme.dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(
          icon,
          size: 20,
          color: isActive
              ? AppColors.volunteerBlue
              : theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        onPressed: onTap,
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(
    BuildContext context,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final isSelected = _filterStatus == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isSelected
                ? AppColors.volunteerBlue
                : theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? AppColors.volunteerBlue
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveChip(
    ThemeData theme,
    String label,
    VoidCallback onDeleted,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.volunteerBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.volunteerBlue.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.volunteerBlue,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onDeleted,
            child: const Icon(
              Icons.close,
              size: 14,
              color: AppColors.volunteerBlue,
            ),
          ),
        ],
      ),
    );
  }
}
