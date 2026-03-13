import 'package:flutter/material.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Enum representing different sections in the Admin Dashboard
enum AdminSection {
  dashboard,
  households,
  donations,
  assistancePacks,
  hrm,
  finalApproval,
  audit,
  reports,
  notifications,
  profile,
  more, // The Grid Hub
  // Phase 5
  purchaseApproval,
  deliveryVerification,
  inventoryIssues,
  // Hybrid Architecture
  fundingControl,
}

/// Enum for household view modes (cards or table)
enum HouseholdViewMode { cards, table }

/// Enum for donation status filters
enum DonationStatusFilter { all, pending, underReview, verified, rejected }

/// Enum for donation type filters
enum DonationTypeFilter { all, generalFund, cash, inKind }

/// @Deprecated('Use AppColors directly')
/// Kept as alias for backward compatibility across 29 usages.
class AdminColors {
  static const Color primaryBlue = AppColors.primaryBlue;
  static const Color accentGreen = AppColors.accentGreen;
}
