import 'package:flutter/material.dart';

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
  // Phase 5
  purchaseApproval,
  deliveryVerification,
  inventoryIssues,
}

/// Enum for household view modes (cards or table)
enum HouseholdViewMode { cards, table }

/// Enum for donation status filters
enum DonationStatusFilter { all, pending, underReview, verified, rejected }

/// Color constants used throughout the Admin Dashboard
class AdminColors {
  static const Color primaryBlue = Color(0xFF5CB9DD);
  static const Color accentGreen = Color(0xFF6DD1A1);
}
