import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';

/// Helper class for Firestore query streams used in Admin Dashboard
/// All queries are capped with .limit() to prevent unbounded reads at scale
class AdminQueries {
  /// Query families by status — archived families are always excluded.
  /// Issue #1 Fix: soft-archived families (isArchived: true) are invisible
  /// in the main admin list while preserving all financial history.
  static Stream<QuerySnapshot<Map<String, dynamic>>> familiesQuery(
    String status,
  ) {
    final base = FirebaseFirestore.instance.collection('families');

    if (status == 'all') {
      return base.orderBy('createdAt', descending: true).limit(200).snapshots();
    } else {
      return base.where('status', isEqualTo: status).limit(200).snapshots();
    }
    // Note: client-side isArchived filtering is applied in households_section.dart
    // because Firestore does not support combining isEqualTo + isNotEqualTo
    // on different fields without a composite index.
  }

  /// Query donations by status filter
  /// NOTE: Draft donations are excluded from admin view - they're only visible to donors
  static Stream<QuerySnapshot<Map<String, dynamic>>> donationsQuery(
    DonationStatusFilter statusFilter,
  ) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'donations',
    );

    // Apply Status Filter
    switch (statusFilter) {
      case DonationStatusFilter.all:
        query = query.where('status', isNotEqualTo: 'draft');
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

    // Note: for 'all' filter (isNotEqualTo), Firestore auto-adds orderBy on 'status',
    // so we can't add a second orderBy without a composite index.
    // For specific status filters, the UI (DonationsSection) handles the sorting
    // client-side to avoid forcing the admin to create manual composite indexes in Firebase.

    return query.limit(200).snapshots();
  }

  /// Query HRM users by role filter
  static Stream<QuerySnapshot<Map<String, dynamic>>> hrmUsersQuery(
    String filter,
  ) {
    final base = FirebaseFirestore.instance.collection('users');

    switch (filter) {
      case 'admin':
        return base
            .where('roles', arrayContains: 'admin')
            .limit(100)
            .snapshots();
      case 'purchaser':
        return base
            .where('roles', arrayContains: 'purchaser')
            .limit(100)
            .snapshots();
      case 'distributor':
        return base
            .where('roles', arrayContains: 'distributor')
            .limit(100)
            .snapshots();
      case 'donor':
        return base
            .where('roles', arrayContains: 'donor')
            .limit(200)
            .snapshots();
      case 'all':
      default:
        // Show all staff and donors
        return base
            .where(
              'roles',
              arrayContainsAny: ['admin', 'purchaser', 'distributor', 'donor'],
            )
            .limit(200)
            .snapshots();
    }
  }
}
