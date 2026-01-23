import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/screens/Donor/models/donor_enums.dart';
import 'package:ration_aid/services/donation_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// My Donations Section - Track and manage donations
class MyDonationsSection extends StatefulWidget {
  const MyDonationsSection({super.key});

  @override
  State<MyDonationsSection> createState() => _MyDonationsSectionState();
}

class _MyDonationsSectionState extends State<MyDonationsSection> {
  final DonationService _donationService = DonationService();
  DonationFilter _selectedFilter = DonationFilter.all;

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'My Donations',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Track your donation journey',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 16),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: DonationFilter.values.map((filter) {
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filter.displayName),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    },
                    selectedColor: AppColors.donorGreen.withOpacity(0.2),
                    checkmarkColor: AppColors.donorGreen,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.donorGreen
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Donations list
          Expanded(
            child: userId == null
                ? const Center(child: Text('Please log in'))
                : StreamBuilder<List<Donation>>(
                    stream: _selectedFilter == DonationFilter.all
                        ? _donationService.streamDonationsByDonor(userId)
                        : _donationService.streamDonationsByDonorAndStatus(
                            userId,
                            _getDonationStatus(_selectedFilter),
                          ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }

                      final donations = snapshot.data ?? [];

                      if (donations.isEmpty) {
                        return Center(
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
                                  ).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: donations.length,
                        itemBuilder: (context, index) {
                          return _DonationCard(donation: donations[index]);
                        },
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
}

/// Donation card widget
class _DonationCard extends StatelessWidget {
  final Donation donation;

  const _DonationCard({required this.donation});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.pushNamed(
              context,
              '/donation-tracking',
              arguments: donation,
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Type icon
                    Icon(
                      donation.donationType == DonationType.cash
                          ? Icons.attach_money
                          : Icons.inventory_2,
                      color: AppColors.donorGreen,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    // Type label
                    Text(
                      donation.donationType.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    // Status badge
                    _StatusBadge(status: donation.status),
                  ],
                ),
                const SizedBox(height: 12),
                // Amount or items
                if (donation.donationType == DonationType.cash &&
                    donation.amount != null)
                  Text(
                    'Amount: Rs. ${donation.amount!.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  )
                else if (donation.items != null)
                  Text(
                    'Items: ${donation.items!.length} types',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                const SizedBox(height: 4),
                // Date
                Text(
                  'Created: ${_formatDate(donation.createdAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// Status badge widget
class _StatusBadge extends StatelessWidget {
  final DonationStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color = _getStatusColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (status) {
      case DonationStatus.draft:
        return DonorColors.statusDraft;
      case DonationStatus.pending:
      case DonationStatus.underVerification:
        return DonorColors.statusPending;
      case DonationStatus.verified:
      case DonationStatus.inProcess:
        return DonorColors.statusVerification;
      case DonationStatus.outForDelivery:
      case DonationStatus.delivered:
        return DonorColors.statusDelivery;
      case DonationStatus.closed:
        return DonorColors.statusCompleted;
      case DonationStatus.rejected:
        return DonorColors.statusRejected;
    }
  }
}
