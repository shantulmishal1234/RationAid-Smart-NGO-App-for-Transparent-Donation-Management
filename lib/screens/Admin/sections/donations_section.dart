import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/utils/admin_queries.dart';
import 'package:ration_aid/screens/Admin/widgets/filters/donation_status_filter.dart';
import 'package:ration_aid/screens/Admin/components/donation_card.dart';
import 'package:ration_aid/screens/Admin/Donation Section/donation_detail_screen.dart';

/// Donations section for managing donor payments
class DonationsSection extends StatelessWidget {
  final DonationStatusFilter donationFilter;
  final ValueChanged<DonationStatusFilter> onFilterChanged;

  const DonationsSection({
    super.key,
    required this.donationFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      key: const ValueKey('donations'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered header
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Donation verification',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Admin-only review of donor payments and impact records.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Filter chips inside soft panel
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            child: DonationStatusFilterChips(
              selected: donationFilter,
              onChanged: onFilterChanged,
            ),
          ),
          const SizedBox(height: 12),

          // List container
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
                stream: AdminQueries.donationsQuery(donationFilter),
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

                  final docs = snapshot.data?.docs ?? [];

                  // Sort by createdAt (oldest first)
                  docs.sort((a, b) {
                    final t1 = a.data()['createdAt'] as Timestamp?;
                    final t2 = b.data()['createdAt'] as Timestamp?;
                    if (t1 == null && t2 == null) return 0;
                    if (t1 == null) return 1;
                    if (t2 == null) return -1;
                    return t1.compareTo(t2);
                  });

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        'No donations for this filter.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final id = docs[index].id;

                      return DonationCard(
                        id: id,
                        serialNumber: index + 1, // NEW
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
      ),
    );
  }
}
