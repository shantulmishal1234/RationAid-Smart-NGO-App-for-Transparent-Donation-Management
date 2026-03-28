import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/screens/Donor/models/donor_enums.dart';
import 'package:ration_aid/services/donation_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_frosted_panel.dart';

/// My Donations Section - Track and manage donations
class MyDonationsSection extends StatefulWidget {
  const MyDonationsSection({super.key});

  @override
  State<MyDonationsSection> createState() => _MyDonationsSectionState();
}

class _MyDonationsSectionState extends State<MyDonationsSection> {
  final DonationService _donationService = DonationService();
  final TextEditingController _searchController = TextEditingController();
  DonationFilter _selectedFilter = DonationFilter.all;
  String _searchQuery = '';

  // P6 Fix — Single cached stream subscription drives both stats panel and list.
  // Previously two separate StreamBuilders queried the same Firestore path,
  // doubling read cost and connection overhead.
  List<Donation> _cachedDonations = [];
  bool _isLoading = true;
  String? _streamError;
  StreamSubscription<List<Donation>>? _donationsSubscription;

  // P2 Fix — Debounce timer: setState fires 300ms after user stops typing.
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isNotEmpty) {
      _donationsSubscription = _donationService
          .streamDonationsByDonor(userId)
          .listen(
            (donations) {
              if (mounted) {
                setState(() {
                  _cachedDonations = donations;
                  _isLoading = false;
                  _streamError = null;
                });
              }
            },
            onError: (Object error) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _streamError = error.toString();
                });
              }
            },
          );
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _donationsSubscription?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // P2 Fix — Debounced search.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value.toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // P6 Fix — compute stats from cached list; no second stream needed
    final donations = _cachedDonations;
    final filteredByStatus = _selectedFilter == DonationFilter.all
        ? donations
        : donations.where((d) {
            final targetStatus = _getDonationStatus(_selectedFilter);
            if (targetStatus == DonationStatus.verified) {
              return d.status == DonationStatus.verified ||
                  d.status == DonationStatus.pendingAssignment;
            }
            return d.status.toFirestore() == targetStatus.toFirestore();
          }).toList();
    final filteredDonations = _searchQuery.isEmpty
        ? filteredByStatus
        : filteredByStatus.where((donation) {
            final type = donation.donationType.displayName.toLowerCase();
            final status = donation.status.displayName.toLowerCase();
            final amount = donation.amount?.toString() ?? '';
            final date =
                '${donation.createdAt.day}/${donation.createdAt.month}/${donation.createdAt.year}';
            return type.contains(_searchQuery) ||
                status.contains(_searchQuery) ||
                amount.contains(_searchQuery) ||
                date.contains(_searchQuery);
          }).toList();

    // Stats from all donations (unfiltered)
    final statusCounts = <String, int>{
      'Total': donations.length,
      'Draft': donations.where((d) => d.status == DonationStatus.draft).length,
      'Under Verification': donations
          .where((d) => d.status == DonationStatus.underVerification)
          .length,
      'Verified': donations
          .where(
            (d) =>
                d.status == DonationStatus.verified ||
                d.status == DonationStatus.pendingAssignment,
          )
          .length,
      'Delivered': donations
          .where((d) => d.status == DonationStatus.delivered)
          .length,
      'Rejected': donations
          .where((d) => d.status == DonationStatus.rejected)
          .length,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Center(
            child: Column(
              children: [
                Text(
                  'My Donations',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Track your donation journey',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // P6 Fix — Overview panel reads from state, no second StreamBuilder
          DonorFrostedPanel(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
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
                    children: statusCounts.entries.map((entry) {
                      return _statItem(
                        entry.key,
                        entry.value.toString(),
                        _getStatusColor(entry.key),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Toolbar: Search | Filter
          Row(
            children: [
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
                      hintText: 'Search donations...',
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
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,

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
                          color: AppColors.donorGreen,
                          width: 1.5,
                        ),
                      ),
                    ),
                    // P2 Fix — debounced search, not setState on every key
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
                child: PopupMenuButton<DonationFilter>(
                  icon: Icon(
                    Icons.filter_list,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    size: 22,
                  ),
                  onSelected: (DonationFilter value) {
                    setState(() {
                      _selectedFilter = value;
                    });
                  },
                  itemBuilder: (BuildContext context) {
                    return DonationFilter.values.map((filter) {
                      return PopupMenuItem<DonationFilter>(
                        value: filter,
                        child: Row(
                          children: [
                            if (_selectedFilter == filter)
                              Icon(
                                Icons.check,
                                size: 18,
                                color: AppColors.donorGreen,
                              ),
                            if (_selectedFilter == filter)
                              const SizedBox(width: 8),
                            Text(
                              filter.displayName,
                              style: TextStyle(
                                color: _selectedFilter == filter
                                    ? AppColors.donorGreen
                                    : theme.colorScheme.onSurface,
                                fontWeight: _selectedFilter == filter
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Donations list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _streamError != null
                // P8 Fix — typed error, not raw error string exposed to user
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_off,
                          size: 56,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _streamError!.contains('PERMISSION_DENIED')
                              ? 'Access denied. Please log in again.'
                              : 'Unable to load donations. Check connection.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                // P6 Fix — use filteredDonations from state (computed in build)
                : filteredDonations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.volunteer_activism,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No donations found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: filteredDonations.length,
                    itemBuilder: (context, index) {
                      return _DonationCard(
                        donation: filteredDonations[index],
                        serialNumber: index + 1,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  DonationStatus _getDonationStatus(DonationFilter filter) {
    switch (filter) {
      case DonationFilter.all:
        return DonationStatus.draft;
      case DonationFilter.draft:
        return DonationStatus.draft;
      case DonationFilter.pending:
        return DonationStatus.pending;
      case DonationFilter.underVerification:
        return DonationStatus.underVerification;
      case DonationFilter.verified:
        return DonationStatus.verified;
      case DonationFilter.inProcess:
        return DonationStatus.inProcess;
      case DonationFilter.outForDelivery:
        return DonationStatus.outForDelivery;
      case DonationFilter.delivered:
        return DonationStatus.delivered;
      case DonationFilter.rejected:
        return DonationStatus.rejected;
    }
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

  /// Get color for donation status
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Total':
        return AppColors.donorGreen;
      case 'Draft':
        return Colors.grey[600]!;
      case 'Under Verification':
        return Colors.orange[700]!;
      case 'Verified':
        return Colors.green[600]!;
      case 'Delivered':
        return Colors.blue[600]!;
      case 'Rejected':
        return Colors.red[600]!;
      default:
        return Colors.grey[600]!;
    }
  }
}

/// Compact donation card widget
class _DonationCard extends StatelessWidget {
  final Donation donation;
  final int serialNumber;

  const _DonationCard({required this.donation, required this.serialNumber});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/donation-tracking',
            arguments: donation,
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.03),
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
                backgroundColor: AppColors.donorGreen.withValues(alpha: 0.1),
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

              // Type Icon
              Icon(
                donation.donationType == DonationType.cash
                    ? Icons.payments
                    : Icons.inventory_2,
                size: 20,
                color: AppColors.donorGreen,
              ),
              const SizedBox(width: 8),

              // Main Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Type + Amount/Items + GRF Badge
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            donation.donationType == DonationType.cash
                                ? 'Cash: Rs. ${donation.amount?.toStringAsFixed(0) ?? '0'}'
                                : 'In-Kind: ${donation.items?.length ?? 0} items',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (donation.familyId == 'general_relief_fund' ||
                            donation.allocationMode == 'general') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Text(
                              'GRF',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Date
                    Text(
                      'Created: ${_formatDate(donation.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusBadgeColor(
                    donation.status,
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _getStatusBadgeColor(
                      donation.status,
                    ).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _getDisplayStatus(donation),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: _getStatusBadgeColor(donation.status),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Arrow icon
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDisplayStatus(Donation d) {
    if ((d.familyId == 'general_relief_fund' ||
            d.allocationMode == 'general') &&
        d.status == DonationStatus.verified) {
      return 'AWAITING ALLOCATION';
    }
    return d.status.displayName.toUpperCase();
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Color _getStatusBadgeColor(DonationStatus status) {
    switch (status) {
      case DonationStatus.draft:
        return Colors.grey[600]!;
      case DonationStatus.pending:
      case DonationStatus.underVerification:
        return Colors.orange[700]!;
      case DonationStatus.verified:
      case DonationStatus.pendingAssignment:
      case DonationStatus.inProcess:
        return Colors.green[600]!;
      case DonationStatus.stocked:
        return const Color(0xFF009688); // Teal — In Warehouse
      case DonationStatus.outForDelivery:
      case DonationStatus.delivered:
        return Colors.blue[600]!;
      case DonationStatus.closed:
        return AppColors.donorGreen;
      case DonationStatus.rejected:
        return Colors.red[600]!;
    }
  }
}
