import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_scaffold.dart';
import 'package:ration_aid/services/funding_service.dart';

/// Family Detail Screen - View masked family information
/// Uses StreamBuilder for real-time updates of needs and funding
class FamilyDetailScreen extends StatefulWidget {
  final Family family; // Initial family object passed from navigation

  const FamilyDetailScreen({super.key, required this.family});

  @override
  State<FamilyDetailScreen> createState() => _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends State<FamilyDetailScreen> {
  @override
  void initState() {
    super.initState();
    // SELF-HEALING: Recalculate family funding on load to ensure stale
    // pendingNeeds/raisedAmount are resolved if data was wiped externally.
    FundingService.recalculateFamilyFunding(widget.family.id);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('families')
          .doc(widget.family.id)
          .snapshots(),
      builder: (context, snapshot) {
        // Use the cached family object passed via routing to eliminate loading flicker.
        // Once the stream emits real-time data, update the object silently.
        Family updatedFamily = widget.family;
        if (snapshot.hasData && snapshot.data!.exists) {
          updatedFamily = Family.fromFirestore(snapshot.data!);
        }

        final isFullyFunded =
            (updatedFamily.totalFunded >= updatedFamily.targetAmount);

        return DonorScaffold(
          title: 'Family Details',
          showBackButton: true,
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom:
                      MediaQuery.of(context).padding.bottom +
                      140, // Ensure content scrolls above CTA
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Hero Header
                    _buildHeroHeader(context, updatedFamily, isFullyFunded),

                    // 2. Success Banner (if fully funded)
                    if (isFullyFunded) _buildSuccessBanner(context),

                    const SizedBox(height: 16),

                    // 3. Precise Financial Progress (if applicable)
                    if (updatedFamily.targetAmount > 0) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildFinancialCard(context, updatedFamily),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 4. Required Items List
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildRequiredItemsCard(context, updatedFamily),
                    ),
                  ],
                ),
              ),

              // Sticky Donate Button
              Align(
                alignment: Alignment.bottomCenter,
                child: _buildStickyDonateCTA(context, updatedFamily),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── HERO HEADER ──────────────────────────────────────────────────
  Widget _buildHeroHeader(
    BuildContext context,
    Family updatedFamily,
    bool isFullyFunded,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  AppColors.donorGreen.withValues(alpha: 0.15),
                  Colors.grey[900]!,
                ]
              : [AppColors.donorGreen.withValues(alpha: 0.1), Colors.white],
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Icon Avatar
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.donorGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.family_restroom,
              size: 48,
              color: isFullyFunded ? Colors.green : AppColors.donorGreen,
            ),
          ),
          const SizedBox(height: 16),

          // Area & URGENT badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${updatedFamily.area}, ${updatedFamily.city}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              if (updatedFamily.isEmergency)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Text(
                    'URGENT',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),

          // Demographics
          Text(
            'Family of ${updatedFamily.familySize} • ${updatedFamily.numberOfAdults} Adults, ${updatedFamily.numberOfChildren} Children',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),

          // Category Badge (Matches Explore Screen exactly)
          _buildCategoryBadge(updatedFamily),
        ],
      ),
    );
  }

  Widget _buildCategoryBadge(Family family) {
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

    final label = isMedicine ? 'Medicine Required' : 'Food Required';
    final iconData = isMedicine
        ? Icons.medical_services_outlined
        : Icons.local_dining;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 16, color: textColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  // ─── SUCCESS BANNER ───────────────────────────────────────────────
  Widget _buildSuccessBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.green.shade600,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Text(
            'This family has been fully supported. Thank you!',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ─── FINANCIAL CARD ───────────────────────────────────────────────
  Widget _buildFinancialCard(BuildContext context, Family family) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final verifiedPct = (family.combinedFundingPercent * 100)
        .clamp(0.0, 100.0)
        .toInt();
    final isFull =
        family.fundingStatus == 'fully_funded' && family.targetAmount > 0;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : AppColors.donorGreen.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Funding Progress',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Metrics
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isFull ? '✓ Goal Reached' : '$verifiedPct% Completed',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: isFull ? Colors.green : AppColors.donorGreen,
                  ),
                ),
                Text(
                  'PKR ${family.combinedProgress.toStringAsFixed(0)} / ${family.targetAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Two-Tier Progress bar
            SizedBox(
              height: 10,
              child: _TwoTierProgressBar(family: family, theme: theme),
            ),

            // Subtext for pending verification
            if (family.pendingAmount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.timer, size: 12, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      'Includes PKR ${family.pendingAmount.toStringAsFixed(0)} pending verification',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
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

  // ─── REQUIRED ITEMS CARD ──────────────────────────────────────────
  Widget _buildRequiredItemsCard(BuildContext context, Family updatedFamily) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : AppColors.donorGreen.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Required Assistance',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Medicine View
            if (updatedFamily.assistanceNeeds.contains('Medicine'))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.medical_services,
                        color: Colors.blue,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Monthly Medical Prescription',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            updatedFamily.customMedicineBudget > 0
                                ? 'Target Budget: PKR ${updatedFamily.customMedicineBudget.toStringAsFixed(0)}/mo'
                                : 'Pending budget assessment',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            // Fully Supplied State (Food)
            else if (updatedFamily.needs.isEmpty &&
                updatedFamily.targetAmount > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'All items have been supplied!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              )
            // Empty / Pending State
            else if (updatedFamily.needs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Pending items assessment',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Awaiting assistance pack assignment by admin',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            // Needs List (Food) - Stable Static Listing
            else
              Column(
                children:
                    (updatedFamily.originalNeeds.isNotEmpty
                            ? updatedFamily.originalNeeds
                            : updatedFamily.needs)
                        .entries
                        .map((entry) {
                          final itemName = entry.key;
                          final originalQty = entry.value;

                          // Get current needed quantity (0 means fully donated)
                          final currentQty = updatedFamily.needs[itemName] ?? 0;
                          final isDonated = currentQty <= 0;

                          // Get localized unit
                          final unit = updatedFamily.itemUnits[itemName] ?? '';
                          final itemQtyDisplay = '$originalQty $unit'.trim();

                          // Dynamic Icon Logic
                          final nameLower = itemName.toLowerCase();
                          IconData itemIcon = Icons.inventory_2_outlined;
                          Color itemColor = AppColors.donorGreen;

                          if (nameLower.contains('flour') ||
                              nameLower.contains('wheat') ||
                              nameLower.contains('aata')) {
                            itemIcon = Icons.grass;
                            itemColor = Colors.orange.shade700;
                          } else if (nameLower.contains('oil') ||
                              nameLower.contains('ghee')) {
                            itemIcon = Icons.water_drop_outlined;
                            itemColor = Colors.amber.shade700;
                          } else if (nameLower.contains('sugar') ||
                              nameLower.contains('salt')) {
                            itemIcon = Icons.grain;
                            itemColor = Colors.grey.shade600;
                          } else if (nameLower.contains('soap') ||
                              nameLower.contains('wash')) {
                            itemIcon = Icons.clean_hands_outlined;
                            itemColor = Colors.blue;
                          } else if (nameLower.contains('rice') ||
                              nameLower.contains('daal') ||
                              nameLower.contains('lentil')) {
                            itemIcon = Icons.rice_bowl_outlined;
                            itemColor = Colors.brown.shade400;
                          }

                          // Check if any pending needs exist for this item
                          num pendingQty =
                              updatedFamily.pendingNeeds[itemName] ?? 0;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: itemColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    itemIcon,
                                    color: itemColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      if (pendingQty > 0)
                                        Text(
                                          '$pendingQty $unit pending verification',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDonated
                                        ? AppColors.donorGreen.withValues(
                                            alpha: 0.1,
                                          )
                                        : (isDark
                                              ? Colors.grey[800]
                                              : Colors.grey[100]),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: isDonated
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.check_circle,
                                              size: 14,
                                              color: AppColors.donorGreen,
                                            ),
                                            const SizedBox(width: 4),
                                            const Text(
                                              'Donated',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: AppColors.donorGreen,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          itemQtyDisplay,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: isDark
                                                ? Colors.white70
                                                : theme.colorScheme.onSurface
                                                      .withValues(alpha: 0.7),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          );
                        })
                        .toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ─── STICKY CTA ───────────────────────────────────────────────────
  Widget _buildStickyDonateCTA(BuildContext context, Family updatedFamily) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bool isFullyFunded =
        updatedFamily.targetAmount > 0 &&
        (updatedFamily.totalFunded >= updatedFamily.targetAmount);
    final bool isNeedsEmpty = updatedFamily.needs.isEmpty;
    final bool isCompleted = isFullyFunded && isNeedsEmpty;

    final String buttonText = isCompleted
        ? 'Fully Supported'
        : isFullyFunded
        ? 'Goal Reached (Pending Validation)'
        : (updatedFamily.raisedAmount > 0)
        ? 'Donate Remaining Amount'
        : 'Donate to this Family';

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.03),
            offset: const Offset(0, -4),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: isCompleted
                ? null
                : () {
                    Navigator.pushNamed(
                      context,
                      '/create-donation',
                      arguments: updatedFamily,
                    );
                  },
            icon: Icon(isCompleted ? Icons.favorite : Icons.volunteer_activism),
            label: Text(
              buttonText,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isCompleted
                  ? Colors.grey.shade400
                  : AppColors.donorGreen,
              foregroundColor: Colors.white,
              elevation: isCompleted ? 0 : 4,
              shadowColor: AppColors.donorGreen.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Precise Two-Tier Progress bar from Explore Screen
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

    final isFull =
        family.fundingStatus == 'fully_funded' && family.targetAmount > 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 10,
        color: theme.brightness == Brightness.dark
            ? Colors.grey[800]
            : Colors.grey[200],
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeOutCubic,
          tween: Tween<double>(begin: 0, end: 1),
          builder: (context, animValue, child) {
            final animVerified = verified * animValue;
            final animPending = pending * animValue;
            return Stack(
              children: [
                // Pending tier (orange, behind)
                FractionallySizedBox(
                  widthFactor: animPending,
                  child: Container(color: Colors.orange.shade300),
                ),
                // Verified tier (green, on top)
                FractionallySizedBox(
                  widthFactor: animVerified,
                  child: Container(
                    color: isFull
                        ? Colors.green.shade400
                        : AppColors.donorGreen,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
