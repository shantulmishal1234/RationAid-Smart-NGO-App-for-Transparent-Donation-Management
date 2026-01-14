/// Simple TTL cache for admin dashboard data
/// Reduces redundant Firebase calls when switching between sections
class AdminCache {
  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _defaultTtl = Duration(minutes: 2);

  /// Get cached data if available and not expired
  static T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null || entry.isExpired) {
      if (entry != null) _cache.remove(key);
      return null;
    }
    return entry.data as T;
  }

  /// Store data in cache with optional custom TTL
  static void set<T>(String key, T data, {Duration? ttl}) {
    _cache[key] = _CacheEntry(data, DateTime.now().add(ttl ?? _defaultTtl));
  }

  /// Invalidate specific key or entire cache
  static void invalidate([String? key]) {
    if (key != null) {
      _cache.remove(key);
    } else {
      _cache.clear();
    }
  }

  /// Invalidate all keys matching a prefix
  static void invalidatePrefix(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Check if a key exists and is valid
  static bool has(String key) {
    final entry = _cache[key];
    return entry != null && !entry.isExpired;
  }

  /// Get or fetch pattern - returns cached data or fetches if expired
  static Future<T> getOrFetch<T>(
    String key,
    Future<T> Function() fetch, {
    Duration? ttl,
  }) async {
    final cached = get<T>(key);
    if (cached != null) return cached;

    final data = await fetch();
    set(key, data, ttl: ttl);
    return data;
  }
}

class _CacheEntry {
  final dynamic data;
  final DateTime expiry;

  _CacheEntry(this.data, this.expiry);

  bool get isExpired => DateTime.now().isAfter(expiry);
}

/// Cache keys as constants for consistency
class CacheKeys {
  static const String dashboardStats = 'dashboard_stats';
  static const String familyCounts = 'family_counts';
  static const String memberCounts = 'member_counts';
  static const String householdOverview = 'household_overview';
}
