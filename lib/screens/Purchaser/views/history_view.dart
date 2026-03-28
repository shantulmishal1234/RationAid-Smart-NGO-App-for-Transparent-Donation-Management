import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/screens/Purchaser/widgets/procurement_card.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/widgets/frosted_panel.dart';
import 'package:ration_aid/services/report_pdf_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HistoryView extends StatefulWidget {
  final bool isSupervisor;
  const HistoryView({super.key, required this.isSupervisor});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  String _filterStatus = 'All'; // All, Active, Delivered, Rejected

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  // Date state
  DateTimeRange? _selectedDateRange;

  // Optimized Data Cache
  late Stream<List<ProcurementRequest>> _historyStream;
  List<ProcurementRequest> _allHistoryRequests = [];
  List<ProcurementRequest> _filteredRequests = [];

  // Stats Cache
  int _processedCountAllTime = 0;
  double _totalValueAllTime = 0;
  int _activeCountAllTime = 0;
  int _deliveredCountAllTime = 0;

  @override
  void initState() {
    super.initState();
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _historyStream = ProcurementService.getSmartHistoryStream(
      uid,
      widget.isSupervisor,
    );
  }

  void _processData(List<ProcurementRequest> allRequests) {
    // 1. Base Filter: Post-purchase processes
    _allHistoryRequests = allRequests.where((r) {
      return r.status == ProcurementStatus.verified ||
          r.status == ProcurementStatus.stocked ||
          r.status == ProcurementStatus.delivered ||
          r.status == ProcurementStatus.rejected ||
          r.status == ProcurementStatus.issue_reported ||
          r.status == ProcurementStatus.written_off;
    }).toList();

    // 2. Stats Calculation (Before View Filters)
    _processedCountAllTime = _allHistoryRequests.length;
    _totalValueAllTime = _allHistoryRequests.fold<double>(
      0,
      (sum, r) => sum + r.totalSpent,
    );
    _activeCountAllTime = _allHistoryRequests
        .where(
          (r) =>
              r.status == ProcurementStatus.verified ||
              r.status == ProcurementStatus.stocked,
        )
        .length;
    _deliveredCountAllTime = _allHistoryRequests
        .where((r) => r.status == ProcurementStatus.delivered)
        .length;

    _applyFilters();
  }

  void _applyFilters() {
    var filtered = List<ProcurementRequest>.from(_allHistoryRequests);

    // 3. Apply View Filters (Status)
    if (_filterStatus != 'All') {
      filtered = filtered.where((r) {
        if (_filterStatus == 'Active') {
          return r.status == ProcurementStatus.verified ||
              r.status == ProcurementStatus.stocked ||
              r.status == ProcurementStatus.issue_reported;
        }
        if (_filterStatus == 'Delivered') {
          return r.status == ProcurementStatus.delivered ||
              r.status == ProcurementStatus.written_off;
        }
        if (_filterStatus == 'Rejected') {
          return r.status == ProcurementStatus.rejected;
        }
        return true;
      }).toList();
    }

    // 4. Apply Date Filter
    if (_selectedDateRange != null) {
      filtered = filtered.where((r) {
        final dateToCheck = r.verifiedAt ?? r.createdAt;
        return dateToCheck.isAfter(
              _selectedDateRange!.start.subtract(const Duration(seconds: 1)),
            ) &&
            dateToCheck.isBefore(
              _selectedDateRange!.end.add(const Duration(days: 1)),
            );
      }).toList();
    }

    // 5. Apply Search
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((r) {
        return r.packName.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    // 6. Sort
    filtered.sort((a, b) {
      final dateA = a.verifiedAt ?? a.createdAt;
      final dateB = b.verifiedAt ?? b.createdAt;
      return dateB.compareTo(dateA);
    });

    _filteredRequests = filtered;
  }

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
          _applyFilters();
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
              primary: AppColors.purchaserOrange,
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
      setState(() {
        _selectedDateRange = picked;
        _applyFilters();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM dd, yyyy');

    return StreamBuilder<List<ProcurementRequest>>(
      stream: _historyStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _allHistoryRequests.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasData) {
          _processData(snapshot.data!);
        }

        final filteredCount = _filteredRequests.length;
        // Unused: final filteredValue = historyRequests.fold...

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Header ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'Purchase History',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // --- Quick Stats Dashboard (Inventory Style) ---
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
                    // Total Value
                    Expanded(
                      child: _buildStatItem(
                        theme,
                        'Rs ${(_totalValueAllTime / 1000).toStringAsFixed(1)}K',
                        'Total Spent',
                        AppColors.purchaserOrange,
                      ),
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: theme.dividerColor.withValues(alpha: 0.5),
                    ),
                    // Processed
                    Expanded(
                      child: _buildStatItem(
                        theme,
                        _processedCountAllTime.toString(),
                        'Processed',
                        Colors.blue,
                      ),
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: theme.dividerColor.withValues(alpha: 0.5),
                    ),
                    // Active
                    Expanded(
                      child: _buildStatItem(
                        theme,
                        _activeCountAllTime.toString(),
                        'Active',
                        Colors.orange,
                      ),
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: theme.dividerColor.withValues(alpha: 0.5),
                    ),
                    // Delivered
                    Expanded(
                      child: _buildStatItem(
                        theme,
                        _deliveredCountAllTime.toString(),
                        'Delivered',
                        Colors.green,
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

                  // Status Filter Button
                  _buildFilterButton(
                    theme: theme,
                    icon: _filterStatus == 'All'
                        ? Icons.filter_list
                        : Icons.filter_list_alt,
                    tooltip: 'Filter Status',
                    isActive: _filterStatus != 'All',
                    onTap: () {}, // Handled by PopupMenu
                    child: PopupMenuButton<String>(
                      offset: const Offset(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tooltip: 'Filter Status',
                      onSelected: (value) => setState(() {
                        _filterStatus = value;
                        _applyFilters();
                      }),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'All',
                          child: Text('All Processes'),
                        ),
                        const PopupMenuItem(
                          value: 'Active',
                          child: Text('Verified / Active'),
                        ),
                        const PopupMenuItem(
                          value: 'Delivered',
                          child: Text('Delivered Only'),
                        ),
                        const PopupMenuItem(
                          value: 'Rejected',
                          child: Text('Rejected'),
                        ),
                      ],
                      child: Icon(
                        _filterStatus == 'All'
                            ? Icons.filter_list
                            : Icons.filter_list_alt,
                        size: 20,
                        color: _filterStatus == 'All'
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                            : AppColors.purchaserOrange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Date Filter Button
                  _buildFilterButton(
                    theme: theme,
                    icon: Icons.calendar_month_outlined,
                    tooltip: 'Filter Date',
                    isActive: _selectedDateRange != null,
                    onTap: () {},
                    child: PopupMenuButton<String>(
                      offset: const Offset(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tooltip: 'Filter Date',
                      onSelected: (value) {
                        if (value == 'clear') {
                          setState(() {
                            _selectedDateRange = null;
                            _applyFilters();
                          });
                        } else if (value == 'custom')
                          _showCustomRangePicker();
                        else {
                          final now = DateTime.now();
                          DateTime start = now;
                          if (value == 'today') {
                            start = DateTime(now.year, now.month, now.day);
                          } else if (value == '7days')
                            start = now.subtract(const Duration(days: 6));
                          else if (value == '30days')
                            start = now.subtract(const Duration(days: 29));
                          else if (value == 'month')
                            start = DateTime(now.year, now.month, 1);

                          final end = DateTime(
                            now.year,
                            now.month,
                            now.day,
                            23,
                            59,
                            59,
                          );
                          setState(() {
                            _selectedDateRange = DateTimeRange(
                              start: start,
                              end: end,
                            );
                            _applyFilters();
                          });
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'today',
                          child: Text('Today'),
                        ),
                        const PopupMenuItem(
                          value: '7days',
                          child: Text('Last 7 Days'),
                        ),
                        const PopupMenuItem(
                          value: '30days',
                          child: Text('Last 30 Days'),
                        ),
                        const PopupMenuItem(
                          value: 'month',
                          child: Text('This Month'),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'custom',
                          child: Text('Custom Range...'),
                        ),
                        if (_selectedDateRange != null)
                          const PopupMenuItem(
                            value: 'clear',
                            child: Text(
                              'Clear Filter',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                      child: Icon(
                        Icons.calendar_month_outlined,
                        size: 20,
                        color: _selectedDateRange == null
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                            : AppColors.purchaserOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Result Count Text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing $filteredCount records',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (_selectedDateRange != null)
                    Text(
                      '${dateFormat.format(_selectedDateRange!.start)} - ${dateFormat.format(_selectedDateRange!.end)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.purchaserOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // --- Main List ---
            Expanded(
              child: FrostedPanel(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                padding: EdgeInsets.zero,
                child: _filteredRequests.isEmpty
                    ? Center(
                        child: Text(
                          'No records found',
                          style: TextStyle(color: theme.disabledColor),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                          itemCount: _filteredRequests.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(
                            height: 12,
                          ), // Match Inventory spacing
                          itemBuilder: (context, index) {
                            if (index == _filteredRequests.length) {
                              // Export Button at bottom
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                child: Center(
                                  child: TextButton.icon(
                                    onPressed: () {
                                      ReportPdfService.generateAndOpenReport(
                                        _filteredRequests,
                                        _selectedDateRange,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.picture_as_pdf,
                                      size: 18,
                                    ),
                                    label: const Text('Export List (PDF)'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: theme.primaryColor,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final request = _filteredRequests[index];
                            return ProcurementCard(
                              request: request,
                              actionLabel: 'Details',
                              onTap: () =>
                                  _showEnhancedDetails(context, request),
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
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterButton({
    required ThemeData theme,
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Container(
      height: 46,
      width: 46,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.purchaserOrange
              : theme.dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: Center(child: child),
    );
  }

  void _showEnhancedDetails(BuildContext context, ProcurementRequest request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      request.packName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: request.status == ProcurementStatus.verified
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      request.status.toString().split('.').last.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: request.status == ProcurementStatus.verified
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 30),

            // Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  // Stats Row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Amount',
                              style: TextStyle(
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                            Text(
                              'Rs ${request.totalSpent.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Date',
                              style: TextStyle(
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                            Text(
                              DateFormat(
                                'MMM dd, yyyy',
                              ).format(request.verifiedAt ?? request.createdAt),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Items Table
                  Text(
                    'Purchased Items',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: request.items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${item.quantity}  -  Rs ${item.actualCost.toStringAsFixed(0)}',
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  if (request.adminRemarks != null &&
                      request.adminRemarks!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: FrostedPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Admin Remarks',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(request.adminRemarks!),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 30),
                  if (request.receiptUrl != null &&
                      request.receiptUrl!.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () {
                        // Show full screen image
                        showDialog(
                          context: context,
                          builder: (_) =>
                              Dialog(child: Image.network(request.receiptUrl!)),
                        );
                      },
                      icon: const Icon(Icons.receipt),
                      label: const Text('View Receipt'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
