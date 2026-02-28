import 'package:flutter/material.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/screens/Donor/Donation/create_donation_screen.dart';
import 'package:ration_aid/screens/Donor/Donation/donation_tracking_screen.dart';
import 'package:ration_aid/screens/Donor/Family/family_detail_screen.dart';

/// Route generator for donor module screens
class DonorRoutes {
  static Route<dynamic>? generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/create-donation':
        // Can receive either Family (for new donation) or Donation (for editing)
        final args = settings.arguments;
        if (args is Donation) {
          return MaterialPageRoute(
            builder: (_) => CreateDonationScreen(existingDonation: args),
          );
        } else {
          final family = args is Family ? args : null;
          return MaterialPageRoute(
            builder: (_) => CreateDonationScreen(selectedFamily: family),
          );
        }

      case '/donation-tracking':
        final args = settings.arguments;
        if (args is! Donation) return null;
        return MaterialPageRoute(
          builder: (_) => DonationTrackingScreen(donation: args),
        );

      case '/family-detail':
        final args = settings.arguments;
        if (args is! Family) return null;
        return MaterialPageRoute(
          builder: (_) => FamilyDetailScreen(family: args),
        );

      default:
        return null;
    }
  }
}
