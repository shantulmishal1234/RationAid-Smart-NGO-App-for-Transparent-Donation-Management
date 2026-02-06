import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/utils/admin_queries.dart';
import 'package:ration_aid/screens/Admin/utils/admin_helpers.dart';

import 'package:ration_aid/screens/Admin/components/donation_card.dart';
import 'package:ration_aid/screens/Admin/Donation Section/donation_detail_screen.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/services/funding_service.dart';

/// Donations section for managing donor payments
class DonationsSection extends StatefulWidget {
  final DonationStatusFilter donationFilter;
  final ValueChanged<DonationStatusFilter> onFilterChanged;

  const DonationsSection({
    super.key,
    required this.donationFilter,
    required this.onFilterChanged,
  });

  @override
  State<DonationsSection> createState() => _DonationsSectionState();
}

class _DonationsSectionState extends State<DonationsSection> {
  final _searchController = TextEditingController();
  String _donationSearch = '';
  Timer? _debounce;
  late Future<Map<String, int>> _overviewFuture;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  void _loadOverview({bool forceRefresh = false}) {
    _overviewFuture = AdminHelpers.loadDonationOverview(
      forceRefresh: forceRefresh,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _donationSearch = value.trim().toLowerCase();
        });
      }
    });
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
              'Donation Verification',
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
          child: Column(
            children: [
              FrostedPanel(
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
                              'pending': 0,
                              'under_verification': 0,
                              'verified': 0,
                              'rejected': 0,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                              label: 'Pending',
                              value: d['pending'].toString(),
                              color: Colors.amber[700]!,
                            ),
                            _overviewChip(
                              context,
                              label: 'Review',
                              value: d['under_verification'].toString(),
                              color: Colors.blue[600]!,
                            ),
                            _overviewChip(
                              context,
                              label: 'Verified',
                              value: d['verified'].toString(),
                              color: Colors.green[600]!,
                            ),
                            _overviewChip(
                              context,
                              label: 'Rejected',
                              value: d['rejected'].toString(),
                              color: Colors.red[400]!,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<Map<String, double>>(
                stream: FundingService.getFundingStatsStream(),
                builder: (context, snapshot) {
                  final stats =
                      snapshot.data ??
                      {'totalTarget': 0.0, 'totalRaised': 0.0, 'totalGap': 0.0};
                  final target = stats['totalTarget']!;
                  final raised = stats['totalRaised']!;
                  final percent = target > 0 ? (raised / target) : 0.0;

                  return FrostedPanel(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.monetization_on,
                              color: Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Funding Pool Status',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            if (target > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${(percent * 100).toInt()}% Funded',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _fundingMetric(
                              context,
                              'Target',
                              target,
                              theme.colorScheme.primary,
                            ),
                            _fundingMetric(
                              context,
                              'Raised',
                              raised,
                              Colors.green,
                            ),
                            _fundingMetric(
                              context,
                              'Gap',
                              stats['totalGap']!,
                              Colors.red,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percent.clamp(0.0, 1.0),
                            backgroundColor: Colors.grey[200],
                            color: Colors.green,
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
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
                child: PopupMenuButton<DonationStatusFilter>(
                  icon: Icon(
                    Icons.filter_list,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    size: 22,
                  ),
                  tooltip: 'Filter by Status',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: widget.onFilterChanged,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: DonationStatusFilter.all,
                      child: Text('All Status'),
                    ),
                    const PopupMenuItem(
                      value: DonationStatusFilter.pending,
                      child: Text('Pending'),
                    ),
                    const PopupMenuItem(
                      value: DonationStatusFilter.underReview,
                      child: Text('Under Review'),
                    ),
                    const PopupMenuItem(
                      value: DonationStatusFilter.verified,
                      child: Text('Verified'),
                    ),
                    const PopupMenuItem(
                      value: DonationStatusFilter.rejected,
                      child: Text('Rejected'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // List container
        Expanded(
          child: FrostedPanel(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: EdgeInsets.zero,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: AdminQueries.donationsQuery(widget.donationFilter),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load donations',
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
                if (_donationSearch.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data();
                    final name = (data['donorName'] ?? '')
                        .toString()
                        .toLowerCase();
                    final email = (data['donorEmail'] ?? '')
                        .toString()
                        .toLowerCase();
                    final method = (data['method'] ?? '')
                        .toString()
                        .toLowerCase();
                    final needle = _donationSearch;
                    return name.contains(needle) ||
                        email.contains(needle) ||
                        method.contains(needle);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: theme.colorScheme.onSurface.withOpacity(0.2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No donations found.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
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

                    return DonationCard(
                      id: id,
                      serialNumber: index + 1,
                      donorName: data['donorName'] ?? 'Unknown donor',
                      donorEmail: data['donorEmail'] ?? '',
                      amount: (data['amount'] ?? 0).toDouble(),
                      currency: data['currency'] ?? 'PKR',
                      method: data['method'] ?? 'cash',
                      status: data['status'] ?? 'pending',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DonationDetailScreen(
                              donationId: id,
                              initialData: data,
                            ),
                          ),
                        );
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

  Widget _fundingMetric(
    BuildContext context,
    String label,
    double value,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        Text(
          value >= 1000
              ? '${(value / 1000).toStringAsFixed(1)}k'
              : value.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
