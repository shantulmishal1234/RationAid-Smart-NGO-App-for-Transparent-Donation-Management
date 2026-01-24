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
      countFamilies(status: 'pending'),
      countFamilies(status: 'rejected'),
      countFamilies(status: 'discarded'),
    ]);

    final data = {
      'total': results[0],
      'accepted': results[1],
      'pending': results[2],
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
      _usersRef.count().get(),
      _usersRef.where('roles', arrayContains: 'volunteer').count().get(),
      _usersRef.where('roles', arrayContains: 'ngo_admin').count().get(),
    ]);

    final data = {
      'total': results[0].count ?? 0,
      'volunteers': results[1].count ?? 0,
      'admins': results[2].count ?? 0,
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
      _familiesRef.where('status', isEqualTo: 'pending').count().get(),
      _familiesRef.where('status', isEqualTo: 'accepted').count().get(),
      _familiesRef.where('status', isEqualTo: 'rejected').count().get(),
      _familiesRef.where('status', isEqualTo: 'discarded').count().get(),
    ]);

    final data = {
      'total': results[0].count ?? 0,
      'pending': results[1].count ?? 0,
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

    // Run both sets of counts in parallel
    final results = await Future.wait([
      loadFamilyCounts(forceRefresh: forceRefresh),
      loadMemberCounts(forceRefresh: forceRefresh),
    ]);

    final familyData = results[0];
    final memberData = results[1];

    final data = {
      'fam_total': familyData['total'] ?? 0,
      'fam_accepted': familyData['accepted'] ?? 0,
      'fam_pending': familyData['pending'] ?? 0,
      'mem_total': memberData['total'] ?? 0,
      'mem_admins': memberData['admins'] ?? 0,
      'mem_volunteers': memberData['volunteers'] ?? 0,
    };

    // Cache the combined results
    AdminCache.set(CacheKeys.dashboardStats, data);
    return data;
  }

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
      donationsRef.where('status', isEqualTo: 'under_review').count().get(),
      donationsRef.where('status', isEqualTo: 'verified').count().get(),
      donationsRef.where('status', isEqualTo: 'rejected').count().get(),
    ]);

    final data = {
      'total': results[0].count ?? 0,
      'pending': results[1].count ?? 0,
      'under_review': results[2].count ?? 0,
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
    ]);

    final data = {
      'total': results[0].count ?? 0,
      'purchaser': results[1].count ?? 0,
      'distributor': results[2].count ?? 0,
      'donor': results[3].count ?? 0,
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
