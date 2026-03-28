import 'package:flutter/material.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/family_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Family Selection Screen - Modal screen for selecting a family to donate to.
///
/// [inKindOnly] — when true, only Food/combined families are shown.
/// Pass this flag when navigating from the In-Kind donation tab (Fix #12).
class FamilySelectionScreen extends StatefulWidget {
  final bool inKindOnly;
  const FamilySelectionScreen({super.key, this.inKindOnly = false});

  @override
  State<FamilySelectionScreen> createState() => _FamilySelectionScreenState();
}

class _FamilySelectionScreenState extends State<FamilySelectionScreen> {
  final FamilyService _familyService = FamilyService();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Select Family',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.donorGreen, AppColors.accentGreen],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by area...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Family list
          Expanded(
            child: StreamBuilder<List<Family>>(
              stream: _familyService.streamAcceptedFamilies(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                var families = snapshot.data ?? [];

                // Fix #12 — filter to food-only families for in-kind donations
                if (widget.inKindOnly) {
                  families = families.where((f) => f.acceptsInKind).toList();
                }

                // Filter by search query
                if (_searchQuery.isNotEmpty) {
                  families = families.where((family) {
                    return family.area.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    );
                  }).toList();
                }

                // Sort families: Non-funded first, then partially funded, fully funded last
                families.sort((a, b) {
                  // Fix #9 — use server-confirmed fundingStatus, not client-computed totalFunded
                  final aFunded = a.fundingStatus == 'fully_funded';
                  final bFunded = b.fundingStatus == 'fully_funded';
                  if (aFunded && !bFunded) return 1;
                  if (!aFunded && bFunded) return -1;
                  return 0;
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
                          _searchQuery.isEmpty
                              ? 'No families available'
                              : 'No families found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: families.length,
                  itemBuilder: (context, index) {
                    return _FamilySelectionCard(
                      family: families[index],
                      onSelect: () {
                        // Return selected family and close screen
                        Navigator.pop(context, families[index]);
                      },
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
}

/// Family selection card widget
class _FamilySelectionCard extends StatelessWidget {
  final Family family;
  final VoidCallback onSelect;

  const _FamilySelectionCard({required this.family, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        // Fix #9 — disable based on server-confirmed fundingStatus
        onTap:
            (family.fundingStatus == 'fully_funded' && family.targetAmount > 0)
            ? null
            : onSelect,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Section: Info Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.donorGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.family_restroom,
                      color: AppColors.donorGreen,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Main Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Area + City + emergency badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${family.area}, ${family.city}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (family.isEmergency)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'URGENT',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Family size
                        Row(
                          children: [
                            Icon(
                              Icons.people,
                              size: 14,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${family.numberOfAdults + family.numberOfChildren} members • ${family.numberOfChildren} children',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Category Badge
                  _CategoryBadge(family: family),
                  const SizedBox(width: 8),

                  // Arrow
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: AppColors.donorGreen.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),

              // Bottom Section: Full-width Progress Bar
              if (family.targetAmount > 0) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Builder(
                      builder: (context) {
                        final verifiedPct =
                            (family.combinedFundingPercent * 100)
                                .clamp(0.0, 100.0)
                                .toInt();
                        final isFull =
                            family.fundingStatus == 'fully_funded' &&
                            family.targetAmount > 0;
                        return Text(
                          isFull ? '✓ Fully Funded' : '$verifiedPct% Completed',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isFull ? Colors.grey : AppColors.donorGreen,
                          ),
                        );
                      },
                    ),
                    Builder(
                      builder: (context) {
                        final progressStr = family.combinedProgress
                            .toStringAsFixed(0);
                        final targetStr = family.targetAmount.toStringAsFixed(
                          0,
                        );
                        return Text(
                          'PKR $progressStr / $targetStr',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _TwoTierProgressBar(family: family, theme: theme),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-tier progress bar showing verified (green) + pending (orange).
class _TwoTierProgressBar extends StatelessWidget {
  final Family family;
  final ThemeData theme;

  const _TwoTierProgressBar({required this.family, required this.theme});

  @override
  Widget build(BuildContext context) {
    final target = family.targetAmount;
    if (target <= 0) return const SizedBox.shrink();

    final verified = family.combinedFundingPercent.clamp(0.0, 1.0);
    final pending = ((family.combinedProgress + family.pendingAmount) / target)
        .clamp(0.0, 1.0);
    final bgColor = theme.brightness == Brightness.dark
        ? Colors.grey[800]!
        : Colors.grey[200]!;

    final isFull =
        family.fundingStatus == 'fully_funded' && family.targetAmount > 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          // Background
          Container(height: 6, color: bgColor),
          // Pending tier (orange, behind)
          FractionallySizedBox(
            widthFactor: pending,
            child: Container(height: 6, color: Colors.orange.shade300),
          ),
          // Verified tier (green, on top)
          FractionallySizedBox(
            widthFactor: verified,
            child: Container(
              height: 6,
              color: isFull ? Colors.grey : AppColors.donorGreen,
            ),
          ),
        ],
      ),
    );
  }
}

/// Category badge: Medicine vs Food.
class _CategoryBadge extends StatelessWidget {
  final Family family;

  const _CategoryBadge({required this.family});

  @override
  Widget build(BuildContext context) {
    final isMedicine = family.category == FamilyCategory.medicine;
    final bgColor = isMedicine
        ? Colors.blue.withValues(alpha: 0.1)
        : Colors.orange.withValues(alpha: 0.1);
    final borderColor = isMedicine
        ? Colors.blue.withValues(alpha: 0.3)
        : Colors.orange.withValues(alpha: 0.3);
    final textColor = isMedicine
        ? Colors.blue.shade700
        : Colors.orange.shade800;

    final label = isMedicine ? 'Medicine' : 'Food';
    final iconData = isMedicine
        ? Icons.medical_services_outlined
        : Icons.local_dining;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
