import 'package:latlong2/latlong.dart';

// ─── NavStep ─────────────────────────────────────────────────────────────────

/// A single maneuver step in a turn-by-turn navigation route.
class NavStep {
  /// Human-readable instruction: "Turn left onto Gulberg Road"
  final String instruction;

  /// Distance of this segment in metres.
  final double distance;

  /// Geographic point where this maneuver begins.
  final LatLng location;

  /// OSRM modifier string: "left", "right", "slight left", "sharp right", etc.
  final String modifier;

  /// OSRM maneuver type: "turn", "depart", "arrive", "new name", "merge", etc.
  final String type;

  const NavStep({
    required this.instruction,
    required this.distance,
    required this.location,
    required this.modifier,
    required this.type,
  });
}

// ─── RouteResult ─────────────────────────────────────────────────────────────

/// The complete result of a successful route fetch.
class RouteResult {
  /// Full polyline points for drawing the route on the map.
  final List<LatLng> points;

  /// Total driving distance in metres (from OSRM).
  final double distanceMeters;

  /// Estimated driving duration in seconds (from OSRM).
  final double durationSeconds;

  /// Ordered list of turn-by-turn steps.
  final List<NavStep> steps;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
  });
}
