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
  /// Query donations by status and type filter
  /// NOTE: Draft donations are excluded from admin view
  static Stream<QuerySnapshot<Map<String, dynamic>>> donationsQuery(
    DonationStatusFilter statusFilter, {
    DonationTypeFilter typeFilter = DonationTypeFilter.all,
  }) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'donations',
    );

    // 1. Apply Status Filter
    switch (statusFilter) {
      case DonationStatusFilter.all:
        query = query.where('status', whereNotIn: ['draft']);
        break;
      case DonationStatusFilter.pending:
        query = query.where('status', isEqualTo: 'pending');
        break;
      case DonationStatusFilter.underReview:
        query = query.where('status', isEqualTo: 'under_verification');
        break;
      case DonationStatusFilter.verified:
        query = query.where('status', isEqualTo: 'verified');
        break;
      case DonationStatusFilter.rejected:
        query = query.where('status', isEqualTo: 'rejected');
        break;
    }

    // 2. Apply Type Filter
    // Note: Firestore Composite Index might be required for new combinations
    switch (typeFilter) {
      case DonationTypeFilter.generalFund:
        query = query.where('familyId', isEqualTo: 'general_relief_fund');
        break;
      case DonationTypeFilter.family:
        // 'isNotEqualTo' is supported but can't be combined with 'status != draft' (whereNotIn)
        // usually. We'll rely on client side filter for 'family' strictly if needed,
        // or just strictly filter for general_relief_fund when asked.
        // For now, let's keep it simple: if 'family', we might need to filter client side
        // or just rely on 'generalFund' being the main specific filter.
        // Let's rely on client side filtering for 'family' to avoid "inequality on different fields" issues
        // if status uses 'whereNotIn'.
        // Actually, let's just use 'isEqualTo' for General Fund, which is safe.
        // For 'family', we can't easily do 'familyId != general_relief_fund' efficiently with other filters.
        // So we will filter 'family' type on the client side in the StreamBuilder or use a property check?
        // Let's skip direct query for 'family' type to avoid index hell and do it in UI.
        break;
      case DonationTypeFilter.all:
        break;
    }

    return query.snapshots();
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
