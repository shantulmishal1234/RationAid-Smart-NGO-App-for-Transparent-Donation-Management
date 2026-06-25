import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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
  List<Donation> _cachedDonations = [];
  bool _isLoading = true;
  String? _streamError;
  StreamSubscription<List<Donation>>? _donationsSubscription;

  // P2 Fix — Debounce timer: setState fires 300ms after user stops typing.
  Timer? _searchDebounce;

  // Smart Give Badge Resolution — batch-resolved once after donations load.
  // Stores the actual worst-performing-slice status per parent donation ID.
  Map<String, DonationStatus> _resolvedStatuses = {};
  bool _isResolvingStatuses = false;

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
                // Filter out GRF allocation pseudo-docs — these are internal
                // ledger records (donorId='grf_allocation') that should never
                // appear in the donor's personal donation list. The original
                // GRF donation card already shows allocation details inline.
                final filtered = donations
                    .where((d) => d.donorId != 'grf_allocation')
                    .toList();
                setState(() {
                  _cachedDonations = filtered;
                  _isLoading = false;
                  _streamError = null;
                });
                // Batch-resolve smart donation statuses after list updates
                _batchResolveSmartStatuses(filtered);
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

  /// Batch-fetches ALL child slice statuses for ALL smart donations in one
  /// Firestore `whereIn` query (max 29 per chunk). Computes the worst-rank
  /// (earliest lifecycle) status per parent and caches in [_resolvedStatuses].
  Future<void> _batchResolveSmartStatuses(List<Donation> donations) async {
    if (_isResolvingStatuses) return;

    final smartDonations = donations
        .where(
          (d) =>
              d.allocationMode == 'smart' && (d.smartSplits?.length ?? 0) > 1,
        )
        .toList();

    if (smartDonations.isEmpty) return;

    _isResolvingStatuses = true;

    const order = [
      'draft',
      'pending',
      'under_verification',
      'verified',
      'stocked',
      'in_process',
      'out_for_delivery',
      'delivered',
      'closed',
    ];

    final Map<String, DonationStatus> resolved = {};
    final parentIds = smartDonations.map((d) => d.id).toList();

    try {
      // Firestore whereIn supports max 30 values — process in chunks of 29
      for (int i = 0; i < parentIds.length; i += 29) {
        final chunk = parentIds.sublist(
          i,
          (i + 29) > parentIds.length ? parentIds.length : i + 29,
        );

        final snap = await FirebaseFirestore.instance
            .collection('donations')
            .where('parentDonationId', whereIn: chunk)
            .get();

        // Group slice statuses by parent ID
        final Map<String, List<String>> slicesByParent = {};
        for (final doc in snap.docs) {
          final parentId = doc.data()['parentDonationId'] as String? ?? '';
          final status = doc.data()['status'] as String? ?? 'verified';
          if (parentId.isNotEmpty) {
            slicesByParent.putIfAbsent(parentId, () => []).add(status);
          }
        }

        // ── Two-Tier Algorithm per parent donation ──────────────────────────
        // 'Delivered' only when ALL slices are terminal (delivered/closed).
        // Otherwise: most advanced NON-terminal state wins.
        for (final parentDonation in smartDonations) {
          final parentId = parentDonation.id;
          if (!chunk.contains(parentId)) continue;

          final statuses = slicesByParent[parentId] ?? [];
          if (statuses.isEmpty) continue;

          const terminalStatuses = {'delivered', 'closed'};
          final parentStatusStr = parentDonation.status.toFirestore();
          final parentRank = order.indexOf(parentStatusStr);

          // Apply parent floor to each slice status.
          // For Cash donations, 'stocked' is normalized to 'verified' since
          // cash has no warehouse step in its lifecycle.
          final isCash = parentDonation.donationType == DonationType.cash;
          final floored = statuses.map((st) {
            final normalized = (isCash && st == 'stocked') ? 'verified' : st;
            final r = order.indexOf(normalized);
            return (r >= 0 && r < parentRank) ? parentStatusStr : normalized;
          }).toList();

          final allTerminal = floored.every((s) => terminalStatuses.contains(s));
          String resolvedStr;

          if (allTerminal) {
            resolvedStr = 'delivered';
          } else {
            int bestRank = parentRank >= 0 ? parentRank : 0;
            String bestStatus = parentStatusStr;
            for (final st in floored) {
              if (terminalStatuses.contains(st)) continue;
              final r = order.indexOf(st);
              if (r > bestRank) {
                bestRank = r;
                bestStatus = st;
              }
            }
            resolvedStr = bestStatus;
          }

          resolved[parentId] = DonationStatus.values.firstWhere(
            (e) => e.toFirestore() == resolvedStr,
            orElse: () => parentDonation.status,
          );
        }
      }
    } catch (_) {
      // Non-critical — cards fall back to parent donation.status
    } finally {
      _isResolvingStatuses = false;
    }

    if (mounted) setState(() => _resolvedStatuses = resolved);
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
            switch (_selectedFilter) {
              case DonationFilter.all:
                return true;

              case DonationFilter.draft:
                return d.status == DonationStatus.draft;

              case DonationFilter.pending:
                return d.status == DonationStatus.pending;

              case DonationFilter.underVerification:
                return d.status == DonationStatus.underVerification;

              case DonationFilter.verified:
                // Verified bucket: admin approved but items not yet on their way.
                // Includes pendingAssignment (GRF pool awaiting assignment).
                // Excludes stocked — that belongs in the inWarehouse bucket.
                return d.status == DonationStatus.verified ||
                    d.status == DonationStatus.pendingAssignment;

              case DonationFilter.inWarehouse:
                // In-Kind items physically received at warehouse.
                // Cash donations should never appear here (stocked is
                // remapped to verified for cash in the UI, but the raw
                // Firestore status could still be stocked).
                return d.status == DonationStatus.stocked ||
                    d.status == DonationStatus.inProcess;

              case DonationFilter.outForDelivery:
                return d.status == DonationStatus.outForDelivery;

              case DonationFilter.delivered:
                // Delivered + closed are both terminal success states.
                return d.status == DonationStatus.delivered ||
                    d.status == DonationStatus.closed;

              case DonationFilter.rejected:
                return d.status == DonationStatus.rejected;
            }
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
                      final d = filteredDonations[index];
                      return _DonationCard(
                        donation: d,
                        serialNumber: index + 1,
                        // Pass batch-resolved status for Smart Give donations
                        resolvedStatus: d.allocationMode == 'smart'
                            ? _resolvedStatuses[d.id]
                            : null,
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

  /// Pre-resolved worst-slice status for Smart Give donations.
  /// Null for non-smart donations (uses donation.status directly).
  final DonationStatus? resolvedStatus;

  const _DonationCard({
    required this.donation,
    required this.serialNumber,
    this.resolvedStatus,
  });

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
                    // Family Area
                    if (donation.familyId == 'general_relief_fund' || donation.allocationMode == 'general')
                      Text(
                        'General Relief Fund',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else if (donation.allocationMode == 'smart')
                      Text(
                        'Smart Give Portfolio',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('families').doc(donation.familyId).get(const GetOptions(source: Source.cache)).catchError((_) => FirebaseFirestore.instance.collection('families').doc(donation.familyId).get()),
                        builder: (context, snapshot) {
                          String displayArea = 'Loading Area...';
                          if (snapshot.hasData && snapshot.data!.exists) {
                            final data = snapshot.data!.data() as Map<String, dynamic>?;
                            if (data != null && data['area'] != null) {
                              displayArea = data['city'] != null ? '${data['area']}, ${data['city']}' : data['area'];
                            } else {
                              displayArea = 'Unknown Area';
                            }
                          } else if (snapshot.hasError) {
                            displayArea = 'Unknown Area';
                          }

                          return Text(
                            displayArea,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    // Smart Give progress subtitle
                    if (donation.allocationMode == 'smart' &&
                        (donation.smartSplits?.length ?? 0) > 0) ...[
                      const SizedBox(height: 4),
                      _SmartSplitSubtitle(donation: donation),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Status Badge — uses resolvedStatus for Smart Give donations
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusBadgeColor(
                    resolvedStatus ?? donation.status,
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _getStatusBadgeColor(
                      resolvedStatus ?? donation.status,
                    ).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _getDisplayStatus(donation),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: _getStatusBadgeColor(
                      resolvedStatus ?? donation.status,
                    ),
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
    final effectiveStatus = resolvedStatus ?? d.status;
    if ((d.familyId == 'general_relief_fund' ||
            d.allocationMode == 'general') &&
        effectiveStatus == DonationStatus.verified) {
      return 'AWAITING ALLOCATION';
    }
    // Show "..." while batch resolution is in-flight for smart donations
    if (d.allocationMode == 'smart' &&
        resolvedStatus == null &&
        (d.smartSplits?.length ?? 0) > 1) {
      return d.status.displayName.toUpperCase(); // Show raw as placeholder
    }
    return effectiveStatus.displayName.toUpperCase();
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

/// Live smart-split progress subtitle shown below the date on donation cards.
/// Queries slice documents once and summarises how many families are at each
/// life-cycle milestone.  Renders a mini colour-coded bar + text label.
class _SmartSplitSubtitle extends StatelessWidget {
  final Donation donation;
  const _SmartSplitSubtitle({required this.donation});

  // Status rank — higher = more advanced.
  static const _order = [
    'draft',
    'pending',
    'under_verification',
    'verified',
    'stocked',
    'in_process',
    'out_for_delivery',
    'delivered',
    'closed',
  ];

  static Color _colorFor(String s) {
    switch (s) {
      case 'delivered':
      case 'closed':
        return Colors.green;
      case 'out_for_delivery':
        return Colors.purple;
      case 'in_process':
        return Colors.indigo;
      case 'stocked':
        return Colors.teal;
      case 'verified':
        return Colors.blue;
      case 'under_verification':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  static String _labelFor(String s, int count, int total) {
    switch (s) {
      case 'delivered':
      case 'closed':
        return '$count/$total delivered';
      case 'out_for_delivery':
        return '$count/$total out for delivery';
      case 'in_process':
        return '$count/$total in process';
      case 'stocked':
        return '$count/$total in warehouse';
      case 'verified':
        return '$count/$total verified';
      default:
        return '$count/$total pending';
    }
  }

  Future<Map<String, int>> _fetchSliceStatusCounts() async {
    final Map<String, int> counts = {};
    final parentStatusStr = donation.status.toFirestore();
    final parentRank = _order.indexOf(parentStatusStr);
    final isCash = donation.donationType == DonationType.cash;

    /// Applies the parent floor and cash-type normalization:
    /// 1. If a slice status is earlier than the parent, elevate to parent's status.
    /// 2. For Cash donations, 'stocked' is not a valid lifecycle step — map to 'verified'.
    String applyFloor(String st) {
      // Fix for legacy corrupted data: In-Kind slices should never be in_process
      if (!isCash && st == 'in_process') {
        st = 'stocked';
      }
      // Cash donations never go to warehouse — normalize stocked → verified
      final normalized = (isCash && st == 'stocked') ? 'verified' : st;
      final rank = _order.indexOf(normalized);
      if (rank < 0 || rank >= parentRank) return normalized;
      return parentStatusStr;
    }

    // Primary: query slices tagged with parentDonationId
    var snap = await FirebaseFirestore.instance
        .collection('donations')
        .where('parentDonationId', isEqualTo: donation.id)
        .get();

    // Fallback: use smartSplits list + familyId queries if no slices found
    if (snap.docs.isEmpty && (donation.smartSplits?.isNotEmpty ?? false)) {
      final donorId = FirebaseAuth.instance.currentUser?.uid ?? '';
      final familyIds = donation.smartSplits!
          .map((s) => s['familyId'] as String? ?? '')
          .where((id) => id.isNotEmpty && id != 'general_relief_fund')
          .toSet();
      for (final fid in familyIds) {
        final fSnap = await FirebaseFirestore.instance
            .collection('donations')
            .where('familyId', isEqualTo: fid)
            .where('isSmartSplitSlice', isEqualTo: true)
            .where('donorId', isEqualTo: donorId)
            .limit(1)
            .get();
        if (fSnap.docs.isNotEmpty) {
          final raw = fSnap.docs.first.data()['status'] as String? ?? parentStatusStr;
          final st = applyFloor(raw);
          counts[st] = (counts[st] ?? 0) + 1;
        }
      }
      return counts;
    }

    for (final doc in snap.docs) {
      final raw = doc.data()['status'] as String? ?? parentStatusStr;
      final st = applyFloor(raw);
      counts[st] = (counts[st] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final total =
        donation.smartSplits
            ?.where(
              (s) =>
                  (s['familyId'] as String? ?? '').isNotEmpty &&
                  s['familyId'] != 'general_relief_fund',
            )
            .length ??
        0;
    if (total == 0) return const SizedBox.shrink();

    return FutureBuilder<Map<String, int>>(
      future: _fetchSliceStatusCounts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 10,
                    color: AppColors.donorGreen,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Smart Give • $total families',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.donorGreen,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 0,
                  backgroundColor: AppColors.donorGreen.withValues(alpha: 0.1),
                  color: AppColors.donorGreen.withValues(alpha: 0.3),
                  minHeight: 4,
                ),
              ),
            ],
          );
        }

        final counts = snapshot.data!;

        // ── Two-Tier Algorithm for progress label ───────────────────────────
        // Rule 1: Show 'X/N delivered' ONLY when ALL real-family slices are
        //         at a terminal state (delivered or closed).
        // Rule 2: Otherwise show the most advanced NON-terminal milestone.
        // ─────────────────────────────────────────────────────────────────────────
        const terminalStatuses = {'delivered', 'closed'};
        final totalTerminal = counts.entries
            .where((e) => terminalStatuses.contains(e.key))
            .fold(0, (acc, e) => acc + e.value);
        final totalSlices = counts.values.fold(0, (acc, v) => acc + v);

        String bestStatus;
        int bestCount;

        if (totalTerminal == totalSlices && totalSlices > 0) {
          // All slices are terminal — mission complete
          bestStatus = 'delivered';
          bestCount = totalTerminal;
        } else {
          // Most advanced NON-terminal status, seeded from parent status floor
          bestStatus = donation.status.toFirestore();
          int bestRank = _order.indexOf(bestStatus);
          for (final entry in counts.entries) {
            if (terminalStatuses.contains(entry.key)) continue;
            final rank = _order.indexOf(entry.key);
            if (rank > bestRank) {
              bestRank = rank;
              bestStatus = entry.key;
            }
          }
          bestCount = counts[bestStatus] ?? 0;
          // If bestCount is 0, all non-terminal slices were floored to parentStatus
          if (bestCount == 0) bestCount = totalSlices - totalTerminal;
        }
        final labelText = _labelFor(bestStatus, bestCount, total);
        final barColor = _colorFor(bestStatus);
        final progress = bestCount / total;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 10,
                  color: AppColors.donorGreen,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Smart Give • $labelText',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: barColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: barColor.withValues(alpha: 0.2),
                color: barColor,
                minHeight: 4,
              ),
            ),
          ],
        );
      },
    );
  }
}
