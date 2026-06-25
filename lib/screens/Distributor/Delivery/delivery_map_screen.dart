import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/theme/app_colors.dart';

class NavStep {
  final String instruction; // "Turn left onto XYZ"
  final double distance; // distance segment
  final LatLng location; // where the maneuver starts
  final String modifier; // "left", "right", "straight", etc.
  final String type;

  NavStep({
    required this.instruction,
    required this.distance,
    required this.location,
    required this.modifier,
    required this.type,
  });
}

/// Full-screen OSM map for delivery navigation.
///
/// Shows:
/// - 📍 Family's verified/unverified GPS (blue pin) — from household form
/// - 📍 Distributor's live GPS (green pin — updates every 5 s)
/// - Distance counter between the two
/// - "Navigate with..." bottom sheet (Google Maps / Waze / OSM)
class DeliveryMapScreen extends StatefulWidget {
  final DeliveryAssignment assignment;

  const DeliveryMapScreen({super.key, required this.assignment});

  @override
  State<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends State<DeliveryMapScreen>
    with WidgetsBindingObserver {
  late final MapController _mapController;
  LatLng? _myPosition;
  StreamSubscription<Position>? _positionSub;
  bool _centeredOnFamily = true;
  double? _distanceMeters;

  // Routing State
  List<LatLng> _routePoints = [];
  bool _isNavigating = false;
  double? _drivingDistanceMeters;
  double? _drivingDurationSeconds;
  bool _isFetchingRoute = false;
  DateTime _lastRouteFetch = DateTime.now().subtract(const Duration(hours: 1));

  // Advanced Navigation State
  List<NavStep> _turnSteps = [];
  NavStep? _currentStep;

  DeliveryAssignment get a => widget.assignment;

  LatLng? get _familyLatLng {
    if (a.familyGeoLat == null || a.familyGeoLng == null) return null;
    return LatLng(a.familyGeoLat!, a.familyGeoLng!);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapController = MapController();
    _startTracking();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_positionSub == null) {
        _startTracking();
      }
    } else if (state == AppLifecycleState.paused) {
      _positionSub?.cancel();
      _positionSub = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    super.dispose();
  }

  void _startTracking() async {
    // Request permission
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission permanently denied. '
              'Enable it in device settings to use navigation.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Start streaming
    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 3, // Very frequent for smooth nav
          ),
        ).listen((pos) {
          if (!mounted) return;
          final myLatLng = LatLng(pos.latitude, pos.longitude);
          final heading = pos.heading;

          setState(() {
            _myPosition = myLatLng;
            if (_familyLatLng != null) {
              _distanceMeters = _haversine(myLatLng, _familyLatLng!);
            }

            // Advance turn steps based on location
            if (_turnSteps.isNotEmpty && _currentStep != null) {
              final distToStep = _haversine(myLatLng, _currentStep!.location);
              if (distToStep < 30) {
                // close enough to the step maneuvers
                int idx = _turnSteps.indexOf(_currentStep!);
                if (idx >= 0 && idx < _turnSteps.length - 1) {
                  _currentStep = _turnSteps[idx + 1];
                }
              }
            }
          });

          if (_isNavigating) {
            // Immersive Nav View: Center on user, high zoom, rotate map
            _mapController.move(myLatLng, 17.5);
            if (heading >= 0) {
              _mapController.rotate(heading);
            }

            // Off-route recalculation
            if (_routePoints.isNotEmpty) {
              double minDist = double.infinity;
              for (final pt in _routePoints) {
                final d = _haversine(myLatLng, pt);
                if (d < minDist) minDist = d;
              }
              if (minDist > 100) {
                // 100m off path threshold
                if (DateTime.now().difference(_lastRouteFetch).inSeconds > 10) {
                  debugPrint(
                    '[Nav] Off route! Recalculating... diff: $minDist',
                  );
                  _lastRouteFetch = DateTime.now();
                  _fetchRoute();
                }
              }
            }
          } else if (_centeredOnFamily == false) {
            // Normal tracking without rotation
            _mapController.move(myLatLng, 17);
          }

          if (!_isNavigating && _routePoints.isEmpty) {
            _lastRouteFetch = DateTime.now();
            _fetchRoute();
          }
        });
  }

  /// Haversine distance between two LatLng points, in metres
  double _haversine(LatLng a, LatLng b) {
    const R = 6371000.0; // Earth radius in metres
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final sinHalfLat = math.sin(dLat / 2);
    final sinHalfLon = math.sin(dLon / 2);
    final aa =
        sinHalfLat * sinHalfLat +
        math.cos(lat1) * math.cos(lat2) * sinHalfLon * sinHalfLon;
    return R * 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  String _formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.toStringAsFixed(0)} sec';
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    final hrs = mins ~/ 60;
    final rMins = mins % 60;
    return '${hrs}h ${rMins}m';
  }

  Future<void> _fetchRoute() async {
    if (_myPosition == null || _familyLatLng == null) return;
    if (_isFetchingRoute) return;

    setState(() => _isFetchingRoute = true);

    try {
      final start = '${_myPosition!.longitude},${_myPosition!.latitude}';
      final end = '${_familyLatLng!.longitude},${_familyLatLng!.latitude}';
      final url = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/$start;$end?overview=full&geometries=geojson&steps=true&annotations=true',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes.first;
          final newDistance = (route['distance'] as num?)?.toDouble();
          final newDuration = (route['duration'] as num?)?.toDouble();

          final geometry = route['geometry'];
          final coords = geometry['coordinates'] as List?;
          List<LatLng> newRoutePoints = [];

          if (coords != null) {
            newRoutePoints = coords
                .map((c) => LatLng(c[1] as double, c[0] as double))
                .toList();
          }

          // Parsing Turn-by-Turn Steps
          List<NavStep> stepsList = [];
          final legs = route['legs'] as List?;
          if (legs != null && legs.isNotEmpty) {
            final steps = legs.first['steps'] as List?;
            if (steps != null) {
              for (var s in steps) {
                final man = s['maneuver'];
                if (man != null) {
                  final loc = man['location'] as List?;
                  final dist = (s['distance'] as num?)?.toDouble() ?? 0.0;
                  final type = man['type'] as String? ?? '';
                  final modifier = man['modifier'] as String? ?? '';
                  final name = s['name'] as String? ?? '';

                  String instr = type;
                  if (type == 'turn') {
                    instr =
                        'Turn $modifier${name.isNotEmpty ? ' onto $name' : ''}';
                  } else if (type == 'arrive') {
                    instr = 'Arrive at destination';
                  } else if (type == 'depart') {
                    instr =
                        'Head $modifier${name.isNotEmpty ? ' onto $name' : ''}';
                  } else {
                    instr =
                        '$type $modifier${name.isNotEmpty ? ' onto $name' : ''}';
                  }

                  if (loc != null && loc.length >= 2) {
                    stepsList.add(
                      NavStep(
                        instruction: instr,
                        distance: dist,
                        location: LatLng(loc[1] as double, loc[0] as double),
                        modifier: modifier,
                        type: type,
                      ),
                    );
                  }
                }
              }
            }
          }

          if (mounted) {
            setState(() {
              _drivingDistanceMeters = newDistance;
              _drivingDurationSeconds = newDuration;
              _routePoints = newRoutePoints;
              _turnSteps = stepsList;
              _currentStep = stepsList.isNotEmpty ? stepsList.first : null;
            });

            // Auto fit bounds on first fetch if not navigating yet
            if (!_isNavigating && newRoutePoints.isNotEmpty) {
              _fitBoundsSafely();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Routing error: $e');
    } finally {
      if (mounted) setState(() => _isFetchingRoute = false);
    }
  }

  void _fitBoundsSafely() {
    if (_myPosition == null || _familyLatLng == null) return;
    try {
      final bounds = LatLngBounds.fromPoints([_myPosition!, _familyLatLng!]);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
      );
    } catch (e) {
      debugPrint('Bound fit error: $e');
    }
  }

  void _centerOnFamily() {
    if (_familyLatLng != null) {
      _centeredOnFamily = true;
      _isNavigating = false;
      _mapController.rotate(0);
      _mapController.move(_familyLatLng!, 16);
      setState(() {});
    }
  }

  void _centerOnMe() {
    if (_myPosition != null) {
      _centeredOnFamily = false;
      _mapController.rotate(0);
      _mapController.move(_myPosition!, 16);
      setState(() {});
    }
  }

  Widget _buildTurnBanner(bool isDark) {
    IconData turnIcon = Icons.turn_right;
    Color turnColor = Colors.white;
    final mod = _currentStep!.modifier;

    if (mod.contains('left')) {
      turnIcon = Icons.turn_left;
    } else if (mod.contains('right')) {
      turnIcon = Icons.turn_right;
    } else if (mod.contains('u-turn')) {
      turnIcon = Icons.u_turn_left;
    } else if (_currentStep!.type == 'arrive') {
      turnIcon = Icons.flag;
      turnColor = Colors.greenAccent;
    } else {
      turnIcon = Icons.straight;
    }

    double distToTurn = 0.0;
    if (_myPosition != null) {
      distToTurn = _haversine(_myPosition!, _currentStep!.location);
    }

    return Container(
      color: Colors.green[800],
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(turnIcon, color: turnColor, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDistance(distToTurn),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    _currentStep!.instruction,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final familyLatLng = _familyLatLng;
    final initialCenter =
        familyLatLng ?? const LatLng(30.3753, 69.3451); // Pakistan center

    return Scaffold(
      appBar: (_isNavigating && _currentStep != null)
          ? null
          : AppBar(
              title: Text(
                '${a.familyArea} — Navigation',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              backgroundColor: Colors.transparent,
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            AppColors.volunteerBlue.withValues(alpha: 0.1),
                            AppColors.volunteerBlue.withValues(alpha: 0.05),
                          ]
                        : [AppColors.volunteerBlue, Colors.blueAccent],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
      body: Column(
        children: [
          // ── Distance banner ────────────────────────────────────────────
          if (_isNavigating && _currentStep != null)
            _buildTurnBanner(isDark)
          else if (familyLatLng != null)
            Container(
              color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8F4FD),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  // Location pin status
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: a.familyLocationVerified
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          a.familyLocationVerified
                              ? Icons.verified
                              : Icons.location_on,
                          size: 14,
                          color: a.familyLocationVerified
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          a.familyLocationVerified
                              ? 'Verified GPS'
                              : 'Unverified GPS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: a.familyLocationVerified
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_drivingDistanceMeters != null) ...[
                    const Icon(
                      Icons.directions_car,
                      size: 16,
                      color: AppColors.volunteerBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDistance(_drivingDistanceMeters!),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.volunteerBlue,
                        fontSize: 14,
                      ),
                    ),
                    if (_drivingDurationSeconds != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(${_formatDuration(_drivingDurationSeconds!)})',
                        style: const TextStyle(
                          color: AppColors.volunteerBlue,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ] else if (_distanceMeters != null) ...[
                    const Icon(Icons.straighten, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      _formatDistance(_distanceMeters!),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                    if (_isFetchingRoute) ...[
                      const SizedBox(width: 6),
                      const SizedBox(
                        height: 12,
                        width: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.volunteerBlue,
                        ),
                      ),
                    ],
                  ] else
                    const Text(
                      'Getting your location…',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            )
          else
            Container(
              color: Colors.orange.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(10),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No GPS coordinates stored for this family. '
                      'Capture the family location in the household form first.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),

          // ── Map ────────────────────────────────────────────────────────
          Expanded(
            child: familyLatLng == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_off,
                          size: 64,
                          color: Colors.grey.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No GPS Data Available',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The family location was not captured.\nNavigation is disabled.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: initialCenter,
                          initialZoom: 14,
                          onPositionChanged: (_, __) {
                            // no-op
                          },
                        ),
                        children: [
                          // OSM tile layer
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.rationaid.app',
                          ),

                          // Route line (Polyline)
                          if (_routePoints.isNotEmpty)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _routePoints,
                                  strokeWidth: 5.0,
                                  color: Colors.blueAccent.withValues(
                                    alpha: 0.8,
                                  ),
                                  borderStrokeWidth: 2.0,
                                  borderColor: AppColors.volunteerBlue,
                                ),
                              ],
                            ),

                          // Markers layer
                          MarkerLayer(
                            markers: [
                              // Family destination pin (blue)
                              Marker(
                                point: familyLatLng,
                                width: 60,
                                height: 80,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.volunteerBlue,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.volunteerBlue
                                                .withValues(alpha: 0.4),
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                      child: const Text(
                                        'Family',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.location_pin,
                                      color: AppColors.volunteerBlue,
                                      size: 36,
                                    ),
                                  ],
                                ),
                              ),

                              // My position pin (green)
                              if (_myPosition != null)
                                Marker(
                                  point: _myPosition!,
                                  width: 50,
                                  height: 70,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.green.withValues(
                                                alpha: 0.4,
                                              ),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                        child: const Text(
                                          'You',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.location_pin,
                                        color: Colors.green,
                                        size: 32,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),

                      // ── Control buttons ────────────────────────────────────
                      Positioned(
                        right: 12,
                        bottom: 100,
                        child: Column(
                          children: [
                            _mapButton(
                              icon: Icons.my_location,
                              tooltip: 'My Location',
                              onTap: _centerOnMe,
                              active: !_centeredOnFamily,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            _mapButton(
                              icon: Icons.home_outlined,
                              tooltip: 'Family Location',
                              onTap: _centerOnFamily,
                              active: _centeredOnFamily,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),

          // ── Bottom action bar ──────────────────────────────────────────
          Container(
            color: isDark ? const Color(0xFF121212) : Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_myPosition == null) return;
                      setState(() {
                        _isNavigating = !_isNavigating;
                        if (_isNavigating) {
                          _centeredOnFamily = false;
                          _lastRouteFetch = DateTime.now();
                          _fetchRoute();
                        } else {
                          _centeredOnFamily = true;
                          _centerOnFamily();
                          _fitBoundsSafely();
                        }
                      });
                    },
                    icon: Icon(
                      _isNavigating ? Icons.stop : Icons.navigation,
                      size: 18,
                    ),
                    label: Text(
                      _isNavigating ? 'Stop Navigation' : 'Start Route',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isNavigating
                          ? Colors.red[600]
                          : AppColors.volunteerBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required bool active,
    required bool isDark,
  }) {
    return Material(
      color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: active
                ? Border.all(color: AppColors.volunteerBlue, width: 2)
                : null,
          ),
          child: Icon(
            icon,
            size: 22,
            color: active
                ? AppColors.volunteerBlue
                : (isDark ? Colors.grey[300] : Colors.grey[700]),
          ),
        ),
      ),
    );
  }
}
