import 'package:flutter/material.dart';

/// Enum representing different sections in the Donor Dashboard
enum DonorSection {
  dashboard,
  exploreFamilies,
  myDonations,
  notifications,
  profile,
}

/// Enum for donation status filters in My Donations section
enum DonationFilter {
  all,
  draft,
  pending,
  underVerification,
  verified,
  inProcess,
  outForDelivery,
  delivered,
  rejected;

  String get displayName {
    switch (this) {
      case DonationFilter.all:
        return 'All';
      case DonationFilter.draft:
        return 'Draft';
      case DonationFilter.pending:
        return 'Pending';
      case DonationFilter.underVerification:
        return 'Under Verification';
      case DonationFilter.verified:
        return 'Verified';
      case DonationFilter.inProcess:
        return 'In Process';
      case DonationFilter.outForDelivery:
        return 'Out for Delivery';
      case DonationFilter.delivered:
        return 'Delivered';
      case DonationFilter.rejected:
        return 'Rejected';
    }
  }
}

/// Color constants used throughout the Donor Dashboard
/// Matching the theme from AppColors but donor-specific
class DonorColors {
  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color accentBlue = Color(0xFF5CB9DD);
  static const Color lightGreen = Color(0xFF6DD1A1);

  // Status colors
  static const Color statusDraft = Color(0xFF9E9E9E);
  static const Color statusPending = Color(0xFFFF9800);
  static const Color statusVerification = Color(0xFF2196F3);
  static const Color statusActive = Color(0xFF00BCD4);
  static const Color statusDelivery = Color(0xFF9C27B0);
  static const Color statusCompleted = Color(0xFF4CAF50);
  static const Color statusRejected = Color(0xFFE53935);
}
