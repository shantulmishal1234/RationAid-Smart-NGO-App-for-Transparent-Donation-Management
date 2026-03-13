import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/screens/Admin/utils/admin_cache.dart';

/// Helper class for loading counts and aggregated data from Firestore
/// Optimized with parallel queries and caching for maximum performance
class AdminHelpers {
  static final _familiesRef = FirebaseFirestore.instance.collection('families');
  static final _usersRef = FirebaseFirestore.instance.collection('users');

  /// Count families with optional status filter
  static Future<int> countFamilies({String? status}) async {
    Query<Map<String, dynamic>> query = _familiesRef;
    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }
    final agg = await query.count().get();
    return agg.count ?? 0;
  }

  /// Load family counts by status - PARALLEL execution
  static Future<Map<String, int>> loadFamilyCounts({
    bool forceRefresh = false,
  }) async {
    // Check cache first
    if (!forceRefresh) {
      final cached = AdminCache.get<Map<String, int>>(CacheKeys.familyCounts);
      if (cached != null) return cached;
    }

    // Execute all count queries in parallel for ~5x speedup
    final results = await Future.wait([
      countFamilies(),
      countFamilies(status: 'accepted'),
      countFamilies(status: 'pending_review'),
      countFamilies(status: 'rejected'),
      countFamilies(status: 'discarded'),
    ]);

    final data = {
      'total': results[0],
      'accepted': results[1],
      'pending_review': results[2],
      'rejected': results[3],
      'discarded': results[4],
    };

    // Cache the results
    AdminCache.set(CacheKeys.familyCounts, data);
    return data;
  }

  /// Load member counts by role - PARALLEL execution
  static Future<Map<String, int>> loadMemberCounts({
    bool forceRefresh = false,
  }) async {
    // Check cache first
    if (!forceRefresh) {
      final cached = AdminCache.get<Map<String, int>>(CacheKeys.memberCounts);
      if (cached != null) return cached;
    }

    // Execute all count queries in parallel
    final results = await Future.wait([
      _usersRef
          .where(
            'roles',
            arrayContainsAny: ['admin', 'purchaser', 'distributor'],
          )
          .count()
          .get(),
      _usersRef.where('roles', arrayContains: 'distributor').count().get(),
      _usersRef.where('roles', arrayContains: 'purchaser').count().get(),
      _usersRef.where('roles', arrayContains: 'admin').count().get(),
    ]);

    final data = {
      'total_staff': results[0].count ?? 0,
      'distributors': results[1].count ?? 0,
      'purchasers': results[2].count ?? 0,
      'admins': results[3].count ?? 0,
    };

    // Cache the results
    AdminCache.set(CacheKeys.memberCounts, data);
    return data;
  }

  /// Load household overview statistics - PARALLEL execution
  static Future<Map<String, int>> loadHouseholdOverview({
    bool forceRefresh = false,
  }) async {
    // Check cache first
    if (!forceRefresh) {
      final cached = AdminCache.get<Map<String, int>>(
        CacheKeys.householdOverview,
      );
      if (cached != null) return cached;
    }

    // Execute all count queries in parallel
    final results = await Future.wait([
      _familiesRef.count().get(),
      _familiesRef.where('status', isEqualTo: 'pending_review').count().get(),
      _familiesRef.where('status', isEqualTo: 'accepted').count().get(),
      _familiesRef.where('status', isEqualTo: 'rejected').count().get(),
      _familiesRef.where('status', isEqualTo: 'discarded').count().get(),
    ]);

    final data = {
      'total': results[0].count ?? 0,
      'pending_review': results[1].count ?? 0,
      'accepted': results[2].count ?? 0,
      'rejected': results[3].count ?? 0,
      'discarded': results[4].count ?? 0,
    };

    // Cache the results
    AdminCache.set(CacheKeys.householdOverview, data);
    return data;
  }

  /// Load all dashboard stats at once - FULLY PARALLEL
  static Future<Map<String, int>> loadAllDashboardStats({
    bool forceRefresh = false,
  }) async {
    // Check cache first
    if (!forceRefresh) {
      final cached = AdminCache.get<Map<String, int>>(CacheKeys.dashboardStats);
      if (cached != null) return cached;
    }

    // Run all sets of counts in parallel
    final results = await Future.wait([
      loadFamilyCounts(forceRefresh: forceRefresh),
      loadMemberCounts(forceRefresh: forceRefresh),
      _procurementRef
          .where('status', whereIn: ['verified', 'stocked'])
          .count()
          .get(),
      loadDonationOverview(forceRefresh: forceRefresh),
    ]);

    final familyData = results[0] as Map<String, int>;
    final memberData = results[1] as Map<String, int>;
    final stockCount = (results[2] as AggregateQuerySnapshot).count ?? 0;
    final donationData = results[3] as Map<String, int>;

    final data = {
      'fam_total': familyData['total'] ?? 0,
      'fam_accepted': familyData['accepted'] ?? 0,
      'fam_pending': familyData['pending_review'] ?? 0,
      'fam_rejected': familyData['rejected'] ?? 0,
      'fam_discarded': familyData['discarded'] ?? 0,
      'mem_total_staff': memberData['total_staff'] ?? 0,
      'mem_admins': memberData['admins'] ?? 0,
      'mem_distributors': memberData['distributors'] ?? 0,
      'mem_purchasers': memberData['purchasers'] ?? 0,
      'stock_available': stockCount,
      'donations_total': donationData['total'] ?? 0,
      'donations_to_review':
          (donationData['pending'] ?? 0) +
          (donationData['under_verification'] ?? 0),
    };

    // Cache the combined results
    AdminCache.set(CacheKeys.dashboardStats, data);
    return data;
  }

  static final _procurementRef = FirebaseFirestore.instance.collection(
    'procurement_requests',
  );

  /// Load donation overview statistics - PARALLEL execution
  static Future<Map<String, int>> loadDonationOverview({
    bool forceRefresh = false,
  }) async {
    // Check cache first
    if (!forceRefresh) {
      final cached = AdminCache.get<Map<String, int>>(
        CacheKeys.donationOverview,
      );
      if (cached != null) return cached;
    }

    final donationsRef = FirebaseFirestore.instance.collection('donations');

    // Execute all count queries in parallel
    final results = await Future.wait([
      donationsRef.count().get(),
      donationsRef.where('status', isEqualTo: 'pending').count().get(),
      donationsRef
          .where('status', isEqualTo: 'under_verification')
          .count()
          .get(),
      donationsRef.where('status', isEqualTo: 'verified').count().get(),
      donationsRef.where('status', isEqualTo: 'rejected').count().get(),
    ]);

    final data = {
      'total': results[0].count ?? 0,
      'pending_review': results[1].count ?? 0,
      'under_verification': results[2].count ?? 0,
      'verified': results[3].count ?? 0,
      'rejected': results[4].count ?? 0,
    };

    // Cache the results
    AdminCache.set(CacheKeys.donationOverview, data);
    return data;
  }

  /// Load HRM overview statistics - PARALLEL execution
  static Future<Map<String, int>> loadHrmOverview({
    bool forceRefresh = false,
  }) async {
    // Check cache first
    if (!forceRefresh) {
      final cached = AdminCache.get<Map<String, int>>(CacheKeys.hrmOverview);
      if (cached != null) return cached;
    }

    // Execute all count queries in parallel
    final results = await Future.wait([
      _usersRef.count().get(),
      _usersRef.where('roles', arrayContains: 'purchaser').count().get(),
      _usersRef.where('roles', arrayContains: 'distributor').count().get(),
      _usersRef.where('roles', arrayContains: 'donor').count().get(),
      _usersRef.where('roles', arrayContains: 'admin').count().get(),
    ]);

    final data = {
      'total': results[0].count ?? 0,
      'purchaser': results[1].count ?? 0,
      'distributor': results[2].count ?? 0,
      'donor': results[3].count ?? 0,
      'admin': results[4].count ?? 0,
    };

    // Cache the results
    AdminCache.set(CacheKeys.hrmOverview, data);
    return data;
  }

  /// Invalidate all cached stats (call after data mutations)
  static void invalidateCache() {
    AdminCache.invalidate();
  }
}
