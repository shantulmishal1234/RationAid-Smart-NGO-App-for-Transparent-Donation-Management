import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:ration_aid/models/nav_step_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles all routing logic: fetching, retry, offline cache, and geometry maths.
///
/// Design goals:
/// - Retry up to [_maxRetries] times with exponential back-off.
/// - Cache the last successful route JSON to SharedPreferences keyed by
///   destination (4 d.p. ≈ 11 m accuracy), so offline trips can still
///   display a usable route overlay.
/// - Expose [distanceToPolyline] using proper segment-projection (O(n) but
///   with an early-exit optimisation), replacing the previous O(n) naive scan
///   that compared every vertex with the user's position.
class RoutingService {
  RoutingService._();

  static const String _osrmBase = 'http://router.project-osrm.org/route/v1';
  static const int _maxRetries = 3;
  static const Duration _baseTimeout = Duration(seconds: 10);

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetch a driving route from [origin] to [destination].
  ///
  /// Retries up to [_maxRetries] times with exponential back-off.
  /// Falls back to cached route when all network attempts fail.
  /// Returns `null` only when both network and cache are unavailable.
  static Future<RouteResult?> fetchRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final cacheKey = _cacheKey(destination);

    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final start = '${origin.longitude},${origin.latitude}';
        final end = '${destination.longitude},${destination.latitude}';
        final url = Uri.parse(
          '$_osrmBase/driving/$start;$end'
          '?overview=full&geometries=geojson&steps=true',
        );

        // Increase timeout on each retry attempt
        final timeout = _baseTimeout * (attempt + 1);
        final response = await http.get(url).timeout(timeout);

        if (response.statusCode == 200) {
          final result = _parseResponse(response.body);
          if (result != null) {
            // Persist for offline fallback
            await _cacheRouteBody(cacheKey, response.body);
            return result;
          }
        }
      } catch (e) {
        debugPrint('[RoutingService] Attempt ${attempt + 1} failed: $e');
        if (attempt < _maxRetries - 1) {
          // Exponential back-off: 1s, 2s, 4s …
          await Future.delayed(
            Duration(seconds: math.pow(2, attempt).toInt()),
          );
        }
      }
    }

    // All network attempts failed — try the cache
    debugPrint('[RoutingService] Falling back to cached route.');
    return _getCachedRoute(cacheKey);
  }

  /// Returns the minimum distance in metres from [point] to the nearest
  /// segment of [polyline].
  ///
  /// Uses orthogonal projection onto each segment (not just vertex distance)
  /// for accuracy, with an early-exit once we find a segment under 5 m.
  static double distanceToPolyline(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    if (polyline.length == 1) return _haversine(point, polyline.first);

    double minDist = double.infinity;

    for (int i = 0; i < polyline.length - 1; i++) {
      final d = _pointToSegmentDistance(point, polyline[i], polyline[i + 1]);
      if (d < minDist) {
        minDist = d;
        // Early exit — already very close to the route
        if (minDist < 5.0) break;
      }
    }

    return minDist;
  }

  // ── Parsing ────────────────────────────────────────────────────────────────

  static RouteResult? _parseResponse(String body) {
    try {
      final data = json.decode(body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final distance = (route['distance'] as num?)?.toDouble() ?? 0.0;
      final duration = (route['duration'] as num?)?.toDouble() ?? 0.0;

      // Decode GeoJSON coordinates → LatLng list
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List?;
      final points = <LatLng>[];
      if (coords != null) {
        for (final c in coords) {
          final pair = c as List;
          points.add(LatLng(pair[1] as double, pair[0] as double));
        }
      }

      final steps = _parseSteps(route);

      return RouteResult(
        points: points,
        distanceMeters: distance,
        durationSeconds: duration,
        steps: steps,
      );
    } catch (e) {
      debugPrint('[RoutingService] Parse error: $e');
      return null;
    }
  }

  static List<NavStep> _parseSteps(Map<String, dynamic> route) {
    final steps = <NavStep>[];
    final legs = route['legs'] as List?;
    if (legs == null || legs.isEmpty) return steps;

    final rawSteps = legs.first['steps'] as List?;
    if (rawSteps == null) return steps;

    for (final s in rawSteps) {
      final step = s as Map<String, dynamic>;
      final man = step['maneuver'] as Map<String, dynamic>?;
      if (man == null) continue;

      final loc = man['location'] as List?;
      if (loc == null || loc.length < 2) continue;

      final dist = (step['distance'] as num?)?.toDouble() ?? 0.0;
      final type = man['type'] as String? ?? '';
      final modifier = man['modifier'] as String? ?? '';
      final name = step['name'] as String? ?? '';

      final instruction = _buildInstruction(type, modifier, name);

      steps.add(NavStep(
        instruction: instruction,
        distance: dist,
        location: LatLng(loc[1] as double, loc[0] as double),
        modifier: modifier,
        type: type,
      ));
    }

    return steps;
  }

  static String _buildInstruction(String type, String modifier, String name) {
    final onto = name.isNotEmpty ? ' onto $name' : '';
    switch (type) {
      case 'turn':
        return 'Turn $modifier$onto';
      case 'depart':
        return 'Head $modifier$onto';
      case 'arrive':
        return 'Arrive at destination';
      case 'new name':
        return 'Continue${name.isNotEmpty ? ' onto $name' : ' straight'}';
      case 'merge':
        return 'Merge $modifier$onto';
      case 'on ramp':
        return 'Take ramp $modifier$onto';
      case 'off ramp':
        return 'Take exit$onto';
      case 'fork':
        return 'Keep $modifier$onto';
      case 'end of road':
        return 'Turn $modifier$onto';
      case 'roundabout':
      case 'rotary':
        return 'Enter roundabout';
      case 'exit roundabout':
      case 'exit rotary':
        return 'Exit roundabout$onto';
      case 'use lane':
        return 'Use lane $modifier';
      default:
        final mod = modifier.isNotEmpty ? ' $modifier' : '';
        return '$type$mod$onto';
    }
  }

  // ── Geometry Helpers ───────────────────────────────────────────────────────

  /// Projects [p] onto segment [a]→[b] and returns the distance in metres.
  static double _pointToSegmentDistance(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude, ay = a.latitude;
    final bx = b.longitude, by = b.latitude;
    final px = p.longitude, py = p.latitude;

    final dx = bx - ax;
    final dy = by - ay;

    if (dx == 0 && dy == 0) return _haversine(p, a);

    // Parameter t ∈ [0, 1] of the closest point on segment
    final t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
    final tc = t.clamp(0.0, 1.0);

    final closestLat = ay + tc * dy;
    final closestLng = ax + tc * dx;

    return _haversine(p, LatLng(closestLat, closestLng));
  }

  static double _haversine(LatLng a, LatLng b) {
    const R = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final sinLat = math.sin(dLat / 2);
    final sinLon = math.sin(dLon / 2);
    final aa =
        sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLon * sinLon;
    return R * 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
  }

  // ── Caching ────────────────────────────────────────────────────────────────

  /// Cache key based on destination only (origin changes every 3 m).
  static String _cacheKey(LatLng dest) =>
      'osrm_route_${dest.latitude.toStringAsFixed(4)}_${dest.longitude.toStringAsFixed(4)}';

  static Future<void> _cacheRouteBody(String key, String body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, body);
      await prefs.setInt(
        '${key}_ts',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('[RoutingService] Cache write error: $e');
    }
  }

  static Future<RouteResult?> _getCachedRoute(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt('${key}_ts') ?? 0;
      // Cache valid for 2 hours
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > const Duration(hours: 2).inMilliseconds) return null;

      final body = prefs.getString(key);
      if (body == null) return null;

      return _parseResponse(body);
    } catch (e) {
      debugPrint('[RoutingService] Cache read error: $e');
      return null;
    }
  }
}
