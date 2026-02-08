import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';

/// Helper class for Firestore query streams used in Admin Dashboard
class AdminQueries {
  /// Query families by status
  static Stream<QuerySnapshot<Map<String, dynamic>>> familiesQuery(
    String status,
  ) {
    final base = FirebaseFirestore.instance.collection('families');

    if (status == 'all') {
      return base.snapshots();
    } else {
      return base.where('status', isEqualTo: status).snapshots();
    }
  }

  /// Query donations by status filter
  /// NOTE: Draft donations are excluded from admin view - they're only visible to donors
  static Stream<QuerySnapshot<Map<String, dynamic>>> donationsQuery(
    DonationStatusFilter filter,
  ) {
    final base = FirebaseFirestore.instance.collection('donations');

    switch (filter) {
      case DonationStatusFilter.all:
        // Exclude draft donations - they're only for donors
        return base.where('status', whereNotIn: ['draft']).snapshots();
      case DonationStatusFilter.pending:
        return base.where('status', isEqualTo: 'pending').snapshots();
      case DonationStatusFilter.underReview:
        return base
            .where('status', isEqualTo: 'under_verification')
            .snapshots();
      case DonationStatusFilter.verified:
        return base.where('status', isEqualTo: 'verified').snapshots();
      case DonationStatusFilter.rejected:
        return base.where('status', isEqualTo: 'rejected').snapshots();
    }
  }

  /// Query HRM users by role filter
  static Stream<QuerySnapshot<Map<String, dynamic>>> hrmUsersQuery(
    String filter,
  ) {
    final base = FirebaseFirestore.instance.collection('users');

    switch (filter) {
      case 'admin':
        return base.where('roles', arrayContains: 'admin').snapshots();
      case 'purchaser':
        return base.where('roles', arrayContains: 'purchaser').snapshots();
      case 'distributor':
        return base.where('roles', arrayContains: 'distributor').snapshots();
      case 'donor':
        return base.where('roles', arrayContains: 'donor').snapshots();
      case 'all':
      default:
        // Show all staff and donors
        return base
            .where(
              'roles',
              arrayContainsAny: ['admin', 'purchaser', 'distributor', 'donor'],
            )
            .snapshots();
    }
  }
}
