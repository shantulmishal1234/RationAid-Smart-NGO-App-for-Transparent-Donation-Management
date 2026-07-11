import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/models/nav_step_model.dart';
import 'package:ration_aid/screens/Distributor/Delivery/proof_of_delivery_screen.dart';
import 'package:ration_aid/services/routing_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

// ─── Map Style ────────────────────────────────────────────────────────────────

enum MapStyle { streets, satellite, dark }

extension _MapStyleExt on MapStyle {
  String get label {
    switch (this) {
      case MapStyle.streets:
        return 'Streets';
      case MapStyle.satellite:
        return 'Satellite';
      case MapStyle.dark:
        return 'Dark';
    }
  }

  IconData get icon {
    switch (this) {
      case MapStyle.streets:
        return Icons.map_outlined;
      case MapStyle.satellite:
        return Icons.satellite_alt;
      case MapStyle.dark:
        return Icons.dark_mode_outlined;
    }
  }

  String get urlTemplate {
    switch (this) {
      case MapStyle.streets:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapStyle.satellite:
        // ArcGIS World Imagery — free, no API key.
        // ArcGIS intentionally uses {z}/{y}/{x} (y before x).
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case MapStyle.dark:
        // CartoDB Dark Matter — free, OSM-based, no API key.
        return 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
    }
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

/// Full-screen delivery navigation map — v3 (Next-Level).
///
/// Enhancements over v2:
/// - **Smooth animated camera** via `AnimationController` (350 ms easeOutCubic)
///   replaces the instant `_mapController.move()` snap.
/// - **Shortest-path heading** interpolation — 359°→1° no longer spins 358°.
/// - **Speed-adaptive zoom** — zooms out on highways, zooms in at low speed.
/// - **Look-ahead camera offset** — user appears at bottom-third of screen so
///   more road ahead is visible, exactly like Google Maps.
/// - **Pulsing GPS accuracy ring** on the user marker (repeating AnimationController).
/// - **Split-route polylines** — traveled section turns gray; remaining stays blue.
/// - **Step-change slide animation** — turn banner slides up when a new
///   maneuver triggers (AnimatedSwitcher + SlideTransition).
/// - **Speed-tinted speedometer** in turn banner — color shifts green→yellow→red.
class DeliveryMapScreen extends StatefulWidget {
  final DeliveryAssignment assignment;

  const DeliveryMapScreen({super.key, required this.assignment});

  @override
  State<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends State<DeliveryMapScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── Map ───────────────────────────────────────────────────────────────────
  late final MapController _mapController;
  MapStyle _mapStyle = MapStyle.streets;

  // ── Camera Animation ──────────────────────────────────────────────────────
  // Drives smooth position + zoom + rotation transitions at 60 fps.
  // _onCameraAnimate is the single listener set up in initState.
  late final AnimationController _cameraAnim;
  late final CurvedAnimation _curvedCamera;

  // Animation from/to targets — written before each forward() call.
  LatLng _camFrom = const LatLng(0, 0);
  LatLng _camTo = const LatLng(0, 0);
  double _camFromZoom = 14.0;
  double _camToZoom = 14.0;
  double _camFromRot = 0.0;
  double _camToRot = 0.0;

  // ── Pulse Animation ───────────────────────────────────────────────────────
  // Drives the expanding/fading ring on the user marker.
  late final AnimationController _pulseAnim;

  // ── Location ─────────────────────────────────────────────────────────────
  LatLng? _myPosition;
  double _currentHeading = 0; // 0–360°, 0 = north
  double _currentSpeedKmh = 0; // from GPS in km/h
  StreamSubscription<Position>? _positionSub;
  bool _centeredOnFamily = true;

  // ── Distances ────────────────────────────────────────────────────────────
  double? _distanceMeters; // straight-line fallback distance

  // ── Routing ──────────────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];
  int _routePassedIndex = 0; // how many route vertices user has passed
  bool _isNavigating = false;
  double? _drivingDistanceMeters;
  double? _drivingDurationSeconds;
  double? _remainingDistMeters;
  double? _remainingSeconds;
  bool _isFetchingRoute = false;
  bool _routeFailed = false;
  DateTime _lastRouteFetch = DateTime.now().subtract(const Duration(hours: 1));

  // ── Turn-by-Turn ─────────────────────────────────────────────────────────
  List<NavStep> _turnSteps = [];
  int _currentStepIndex = 0;

  // ── Arrival ──────────────────────────────────────────────────────────────
  bool _arrivedDialogShown = false;
  static const double _arrivalRadiusMeters = 50.0;

  // ── Convenience getters ───────────────────────────────────────────────────
  DeliveryAssignment get _a => widget.assignment;

  LatLng? get _familyLatLng {
    if (_a.familyGeoLat == null || _a.familyGeoLng == null) return null;
    return LatLng(_a.familyGeoLat!, _a.familyGeoLng!);
  }

  NavStep? get _currentStep =>
      (_turnSteps.isNotEmpty && _currentStepIndex < _turnSteps.length)
          ? _turnSteps[_currentStepIndex]
          : null;

  NavStep? get _nextStep =>
      (_turnSteps.isNotEmpty && _currentStepIndex + 1 < _turnSteps.length)
          ? _turnSteps[_currentStepIndex + 1]
          : null;

  double get _routeCompletionFraction {
    if (_turnSteps.length <= 1) return 0;
    return (_currentStepIndex / (_turnSteps.length - 1)).clamp(0.0, 1.0);
  }

  bool get _inNavMode => _isNavigating && _currentStep != null;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapController = MapController();

    // ── Camera animation setup ─────────────────────────────────────────────
    _cameraAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _curvedCamera = CurvedAnimation(
      parent: _cameraAnim,
      curve: Curves.easeOutCubic,
    );
    // Single persistent listener — reads _camFrom/To vars set before forward()
    _cameraAnim.addListener(_onCameraAnimate);

    // ── Pulse animation setup ──────────────────────────────────────────────
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(); // continuous pulse

    _startTracking();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_positionSub == null) _startTracking();
    } else if (state == AppLifecycleState.paused) {
      _positionSub?.cancel();
      _positionSub = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _cameraAnim.dispose();
    _curvedCamera.dispose();
    _pulseAnim.dispose();
    super.dispose();
  }

  // ── Camera Animation Handler ──────────────────────────────────────────────

  /// Called ~60 fps while the camera animation is running.
  /// Interpolates position, zoom and rotation WITHOUT calling setState —
  /// flutter_map updates the map widget internally via ChangeNotifier.
  void _onCameraAnimate() {
    if (!mounted) return;
    final t = _curvedCamera.value; // 0.0→1.0 with easeOutCubic
    final center = _lerpLatLng(_camFrom, _camTo, t);
    final zoom = _camFromZoom + (_camToZoom - _camFromZoom) * t;
    final rot = _camFromRot + (_camToRot - _camFromRot) * t;
    try {
      _mapController.move(center, zoom);
      _mapController.rotate(rot);
    } catch (_) {}
  }

  /// Smoothly animate the camera to [target] with the given [zoom] and
  /// [rotation]. Reads current camera state, snaps the from-values,
  /// then fires the AnimationController.
  void _animateCameraTo({
    required LatLng target,
    required double zoom,
    required double rotation,
    Duration duration = const Duration(milliseconds: 350),
  }) {
    try {
      _camFrom = _mapController.camera.center;
      _camFromZoom = _mapController.camera.zoom;
      _camFromRot = _mapController.camera.rotation;
    } catch (_) {
      // Map widget not yet initialized — fall back to instant move
      try {
        _mapController.move(target, zoom);
        _mapController.rotate(rotation);
      } catch (_) {}
      return;
    }

    _camTo = target;
    _camToZoom = zoom;
    // Use shortest angular path to avoid 359°→1° full-circle spin
    _camToRot = _shortestRotation(_camFromRot, rotation);

    _cameraAnim.duration = duration;
    _cameraAnim.stop();
    _cameraAnim.reset(); // listener fires at t=0 → camera stays at camFrom
    _cameraAnim.forward();
  }

  // ── GPS Tracking ─────────────────────────────────────────────────────────

  void _startTracking() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Location permanently denied — enable in device settings.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 6),
        ));
      }
      return;
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // metres
      ),
    ).listen((pos) {
      if (!mounted) return;

      final myLatLng = LatLng(pos.latitude, pos.longitude);
      final heading = pos.heading >= 0 ? pos.heading : _currentHeading;
      final speedKmh = pos.speed >= 0 ? pos.speed * 3.6 : 0.0;

      setState(() {
        _myPosition = myLatLng;
        _currentHeading = heading;
        _currentSpeedKmh = speedKmh;

        if (_familyLatLng != null) {
          _distanceMeters = _haversine(myLatLng, _familyLatLng!);
        }

        // Advance step index (O(1)) when within 30 m of maneuver point
        if (_currentStep != null) {
          final distToStep = _haversine(myLatLng, _currentStep!.location);
          if (distToStep < 30 && _currentStepIndex < _turnSteps.length - 1) {
            _currentStepIndex++;
          }
        }

        // Update remaining distance & ETA
        if (_isNavigating) _updateRemainingRoute(myLatLng);

        // Track traveled portion of route for split coloring
        if (_routePoints.isNotEmpty) _updatePassedRouteIndex(myLatLng);
      });

      // Arrival check (outside setState — may show dialog)
      if (_isNavigating) _checkArrival(myLatLng);

      // ── Camera control ────────────────────────────────────────────────────
      if (_isNavigating) {
        // Look-ahead target: offset camera forward so user is at bottom-third
        final target = _navCameraTarget(myLatLng, heading, speedKmh);
        final zoom = _navZoom(speedKmh);
        _animateCameraTo(
          target: target,
          zoom: zoom,
          rotation: heading,
          duration: const Duration(milliseconds: 300),
        );

        // Off-route detection using segment projection (O(n) with early exit)
        if (_routePoints.isNotEmpty) {
          final distToRoute =
              RoutingService.distanceToPolyline(myLatLng, _routePoints);
          if (distToRoute > 100 &&
              DateTime.now().difference(_lastRouteFetch).inSeconds > 10) {
            debugPrint(
              '[Nav] Off-route (${distToRoute.toStringAsFixed(0)} m). Recalculating…',
            );
            _lastRouteFetch = DateTime.now();
            _fetchRoute();
          }
        }
      } else if (!_centeredOnFamily) {
        _animateCameraTo(
          target: myLatLng,
          zoom: 17,
          rotation: 0,
          duration: const Duration(milliseconds: 400),
        );
      }

      // Auto-fetch initial route once GPS is available
      if (!_isNavigating && _routePoints.isEmpty && !_isFetchingRoute) {
        _lastRouteFetch = DateTime.now();
        _fetchRoute();
      }
    });
  }

  // ── Routing ──────────────────────────────────────────────────────────────

  Future<void> _fetchRoute() async {
    if (_myPosition == null || _familyLatLng == null) return;
    if (_isFetchingRoute) return;

    setState(() {
      _isFetchingRoute = true;
      _routeFailed = false;
    });

    final result = await RoutingService.fetchRoute(
      origin: _myPosition!,
      destination: _familyLatLng!,
    );

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _drivingDistanceMeters = result.distanceMeters;
        _drivingDurationSeconds = result.durationSeconds;
        _routePoints = result.points;
        _routePassedIndex = 0; // reset split-route tracker
        _turnSteps = result.steps;
        _currentStepIndex = 0;
        _remainingDistMeters = result.distanceMeters;
        _remainingSeconds = result.durationSeconds;
        _routeFailed = false;
        _isFetchingRoute = false;
      });

      if (!_isNavigating && result.points.isNotEmpty) _fitBoundsSafely();
    } else {
      setState(() {
        _routeFailed = true;
        _isFetchingRoute = false;
      });
      _showRouteFailedSnackBar();
    }
  }

  void _showRouteFailedSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not load route. Check your connection.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () {
            if (!mounted) return;
            _lastRouteFetch = DateTime.now();
            _fetchRoute();
          },
        ),
      ),
    );
  }

  void _updateRemainingRoute(LatLng myPos) {
    if (_turnSteps.isEmpty || _currentStepIndex >= _turnSteps.length) return;

    double remaining = 0;
    for (int i = _currentStepIndex; i < _turnSteps.length; i++) {
      remaining += _turnSteps[i].distance;
    }

    // Subtract the already-covered portion of the current step
    final curStep = _turnSteps[_currentStepIndex];
    if (curStep.distance > 0) {
      final distToEnd = _haversine(myPos, curStep.location);
      final covered =
          (curStep.distance - distToEnd).clamp(0.0, curStep.distance);
      remaining = math.max(0, remaining - covered);
    }

    final speedMps =
        _currentSpeedKmh > 5 ? (_currentSpeedKmh / 3.6) : (40.0 / 3.6);
    _remainingDistMeters = remaining;
    _remainingSeconds = remaining / speedMps;
  }

  /// Tracks how far along the route the user has traveled.
  /// Only searches forward from the current index with an early-exit for
  /// performance (O(k) where k = newly covered points, not O(n)).
  void _updatePassedRouteIndex(LatLng pos) {
    if (_routePoints.length < 2) return;

    final searchLimit = math.min(
      _routePoints.length,
      _routePassedIndex + 60, // look max 60 vertices ahead at a time
    );

    int bestIdx = _routePassedIndex;
    double minDist = double.infinity;

    for (int i = _routePassedIndex; i < searchLimit; i++) {
      final d = _haversine(pos, _routePoints[i]);
      if (d < minDist) {
        minDist = d;
        bestIdx = i;
      } else if (d > minDist + 80) {
        break; // distance increasing → past the nearest point
      }
    }

    if (bestIdx > _routePassedIndex) {
      _routePassedIndex = bestIdx;
    }
  }

  // ── Arrival ───────────────────────────────────────────────────────────────

  void _checkArrival(LatLng myPos) {
    if (_arrivedDialogShown || _familyLatLng == null) return;
    if (_haversine(myPos, _familyLatLng!) <= _arrivalRadiusMeters) {
      _arrivedDialogShown = true;
      _stopNavigation();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _showArrivalDialog());
    }
  }

  void _showArrivalDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        icon: const Icon(Icons.check_circle_rounded,
            color: Colors.green, size: 58),
        title: const Text(
          "You've Arrived! 🎉",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
        ),
        content: const Text(
          'You are within 50 metres of the delivery address.\n\n'
          'Would you like to mark this delivery now?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.55),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Stay on Map'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ProofOfDeliveryScreen(assignment: _a)),
              );
            },
            icon: const Icon(Icons.camera_alt, size: 18),
            label: const Text('Mark Delivered',
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Camera / Map Controls ─────────────────────────────────────────────────

  void _fitBoundsSafely() {
    if (_myPosition == null || _familyLatLng == null) return;
    try {
      final bounds = LatLngBounds.fromPoints([_myPosition!, _familyLatLng!]);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
      );
    } catch (e) {
      debugPrint('[Map] Bounds fit error: $e');
    }
  }

  void _centerOnFamily() {
    if (_familyLatLng == null) return;
    setState(() => _centeredOnFamily = true);
    _animateCameraTo(
      target: _familyLatLng!,
      zoom: 16,
      rotation: 0,
      duration: const Duration(milliseconds: 500),
    );
  }

  void _centerOnMe() {
    if (_myPosition == null) return;
    setState(() => _centeredOnFamily = false);
    _animateCameraTo(
      target: _myPosition!,
      zoom: 16,
      rotation: 0,
      duration: const Duration(milliseconds: 500),
    );
  }

  void _zoomIn() {
    try {
      final z = (_mapController.camera.zoom + 1).clamp(1.0, 19.0);
      _mapController.move(_mapController.camera.center, z);
    } catch (_) {}
  }

  void _zoomOut() {
    try {
      final z = (_mapController.camera.zoom - 1).clamp(1.0, 19.0);
      _mapController.move(_mapController.camera.center, z);
    } catch (_) {}
  }

  void _resetNorth() {
    _animateCameraTo(
      target: _mapController.camera.center,
      zoom: _mapController.camera.zoom,
      rotation: 0,
      duration: const Duration(milliseconds: 400),
    );
    setState(() {});
  }

  // ── Navigation Control ────────────────────────────────────────────────────

  void _startNavigation() {
    if (_myPosition == null) return;
    setState(() {
      _isNavigating = true;
      _centeredOnFamily = false;
      _arrivedDialogShown = false;
    });

    // Immediately animate camera into nav mode — user sees the zoom happen
    // before the first GPS tick (avoids the "stuck at overview" lag)
    final initialTarget = _navCameraTarget(_myPosition!, _currentHeading, _currentSpeedKmh);
    _animateCameraTo(
      target: initialTarget,
      zoom: _navZoom(_currentSpeedKmh),
      rotation: _currentHeading,
      duration: const Duration(milliseconds: 600), // slightly slower for drama
    );

    _lastRouteFetch = DateTime.now();
    _fetchRoute();
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _centeredOnFamily = true;
    });

    // Animate back to north-up overview
    if (_familyLatLng != null) {
      _animateCameraTo(
        target: _familyLatLng!,
        zoom: 15,
        rotation: 0,
        duration: const Duration(milliseconds: 600),
      );
    }
    Future.delayed(const Duration(milliseconds: 700), _fitBoundsSafely);
  }

  // ── Map Style Picker ──────────────────────────────────────────────────────

  void _showMapStylePicker() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Map Style',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 18),
            Row(
              children: MapStyle.values.map((style) {
                final sel = _mapStyle == style;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _mapStyle = style);
                        Navigator.pop(ctx);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.volunteerBlue.withValues(alpha: 0.10)
                              : Colors.grey.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: sel
                                ? AppColors.volunteerBlue
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Column(children: [
                          Icon(style.icon,
                              size: 28,
                              color: sel
                                  ? AppColors.volunteerBlue
                                  : Colors.grey[600]),
                          const SizedBox(height: 8),
                          Text(style.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: sel
                                    ? AppColors.volunteerBlue
                                    : Colors.grey[600],
                              )),
                        ]),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Speed-Adaptive Camera Helpers ─────────────────────────────────────────

  /// Zoom level based on current speed.
  /// Faster = more zoomed out so driver can see further ahead.
  double _navZoom(double speedKmh) {
    if (speedKmh < 10) return 18.5; // walking / parked
    if (speedKmh < 30) return 18.0; // slow city
    if (speedKmh < 60) return 17.5; // normal city
    if (speedKmh < 90) return 16.5; // fast road
    return 15.5; // highway
  }

  /// Offsets the camera center ahead of [userPos] in the direction of
  /// [headingDeg] so the user appears at the bottom-third of the screen.
  /// Look-ahead distance scales with speed (more road visible at high speed).
  LatLng _navCameraTarget(LatLng userPos, double headingDeg, double speedKmh) {
    // Look-ahead in metres: 0 m when stationary, up to 200 m at highway speed
    final lookAheadM = speedKmh < 5
        ? 0.0
        : speedKmh < 30
            ? 60.0
            : speedKmh < 60
                ? 110.0
                : 200.0;

    if (lookAheadM == 0) return userPos;

    // Project the look-ahead point on the Earth's surface
    final headingRad = headingDeg * math.pi / 180;
    const R = 6371000.0; // Earth radius in metres
    final dLat = lookAheadM * math.cos(headingRad) / R;
    final dLon = lookAheadM *
        math.sin(headingRad) /
        (R * math.cos(userPos.latitude * math.pi / 180));

    return LatLng(
      userPos.latitude + dLat * 180 / math.pi,
      userPos.longitude + dLon * 180 / math.pi,
    );
  }

  // ── Utilities ────────────────────────────────────────────────────────────

  double _haversine(LatLng a, LatLng b) {
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

  /// Linear interpolation between two LatLng points.
  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// Returns the equivalent of [to] that is at most 180° away from [from],
  /// ensuring the animation takes the shortest angular path.
  double _shortestRotation(double from, double to) {
    double diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return from + diff;
  }

  String _fmtDist(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _fmtDur(double seconds) {
    if (seconds < 60) return '< 1 min';
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    final hrs = mins ~/ 60;
    final rMins = mins % 60;
    return '${hrs}h ${rMins}m';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final familyLatLng = _familyLatLng;
    final initialCenter = familyLatLng ?? const LatLng(30.3753, 69.3451);

    return Scaffold(
      appBar: _inNavMode
          ? null
          : AppBar(
              title: Text('${_a.familyArea} — Navigation',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              backgroundColor: Colors.transparent,
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            AppColors.volunteerBlue.withValues(alpha: 0.10),
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
          // ── Top banner (turn HUD or info bar) ───────────────────────────
          // AnimatedSwitcher drives the slide-in animation each time the
          // step index changes (ValueKey) or nav mode toggles.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.4),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: _inNavMode
                ? _NavTurnBanner(
                    key: ValueKey(_currentStepIndex),
                    currentStep: _currentStep!,
                    nextStep: _nextStep,
                    distToTurn: _myPosition != null
                        ? _haversine(_myPosition!, _currentStep!.location)
                        : 0,
                    remainingDistMeters: _remainingDistMeters,
                    remainingSeconds: _remainingSeconds,
                    speedKmh: _currentSpeedKmh,
                    onStop: _stopNavigation,
                    fmtDist: _fmtDist,
                    fmtDur: _fmtDur,
                  )
                : familyLatLng != null
                    ? _buildInfoBanner(isDark)
                    : _buildNoGpsBanner(),
          ),

          // ── Map ─────────────────────────────────────────────────────────
          Expanded(
            child: familyLatLng == null
                ? _buildNoGpsPlaceholder()
                : Stack(
                    children: [
                      // ── Flutter Map ──────────────────────────────────────
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: initialCenter,
                          initialZoom: 14,
                        ),
                        children: [
                          // Tile layer (style switchable)
                          TileLayer(
                            urlTemplate: _mapStyle.urlTemplate,
                            userAgentPackageName: 'com.rationaid.app',
                          ),

                          // ── Split-route polylines ───────────────────────
                          // 1. Traveled section → muted gray (shows progress)
                          // 2. Remaining section → active blue with outline
                          if (_routePoints.isNotEmpty)
                            PolylineLayer(
                              polylines: [
                                // Traveled (gray)
                                if (_routePassedIndex >= 1)
                                  Polyline(
                                    points: _routePoints.sublist(
                                        0, _routePassedIndex + 1),
                                    strokeWidth: 4.5,
                                    color: Colors.blueGrey.withValues(alpha: 0.40),
                                  ),
                                // Remaining — shadow outline
                                if (_routePoints.length - _routePassedIndex >= 2)
                                  Polyline(
                                    points:
                                        _routePoints.sublist(_routePassedIndex),
                                    strokeWidth: 10.0,
                                    color: AppColors.volunteerBlue
                                        .withValues(alpha: 0.18),
                                  ),
                                // Remaining — main line
                                if (_routePoints.length - _routePassedIndex >= 2)
                                  Polyline(
                                    points:
                                        _routePoints.sublist(_routePassedIndex),
                                    strokeWidth: 5.5,
                                    color: AppColors.volunteerBlue
                                        .withValues(alpha: 0.92),
                                    borderStrokeWidth: 1.5,
                                    borderColor:
                                        Colors.white.withValues(alpha: 0.55),
                                  ),
                              ],
                            ),

                          // Markers
                          MarkerLayer(
                            markers: [
                              // Family destination pin
                              Marker(
                                point: familyLatLng,
                                width: 72,
                                height: 92,
                                child: _FamilyMarker(
                                    verified: _a.familyLocationVerified),
                              ),
                              // User position — animated heading + pulsing ring
                              if (_myPosition != null)
                                Marker(
                                  point: _myPosition!,
                                  width: 64,
                                  height: 64,
                                  child: _YouMarker(
                                    heading: _currentHeading,
                                    isNavigating: _isNavigating,
                                    pulse: _pulseAnim,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),

                      // ── Route progress bar ────────────────────────────────
                      if (_isNavigating && _turnSteps.isNotEmpty)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: _RouteProgressBar(
                            fraction: _routeCompletionFraction,
                          ),
                        ),

                      // ── Map FABs ──────────────────────────────────────────
                      _buildMapControls(isDark),
                    ],
                  ),
          ),

          // ── Bottom action bar (always visible) ──────────────────────────
          _buildBottomBar(isDark, familyLatLng),
        ],
      ),
    );
  }

  // ── Sub-builders ──────────────────────────────────────────────────────────

  Widget _buildInfoBanner(bool isDark) {
    return Container(
      key: const ValueKey('info'),
      color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8F4FD),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        _GpsChip(verified: _a.familyLocationVerified),
        const Spacer(),
        if (_drivingDistanceMeters != null) ...[
          const Icon(Icons.directions_car,
              size: 16, color: AppColors.volunteerBlue),
          const SizedBox(width: 6),
          Text(_fmtDist(_drivingDistanceMeters!),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.volunteerBlue,
                fontSize: 14,
              )),
          if (_drivingDurationSeconds != null) ...[
            const SizedBox(width: 5),
            Text('(${_fmtDur(_drivingDurationSeconds!)})',
                style: const TextStyle(
                  color: AppColors.volunteerBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                )),
          ],
        ] else if (_routeFailed) ...[
          const Icon(Icons.wifi_off, size: 15, color: Colors.red),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              _lastRouteFetch = DateTime.now();
              _fetchRoute();
            },
            child: const Text('Route failed — tap to retry',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                )),
          ),
        ] else if (_distanceMeters != null) ...[
          const Icon(Icons.straighten, size: 15, color: Colors.grey),
          const SizedBox(width: 6),
          Text(_fmtDist(_distanceMeters!),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.grey,
                fontSize: 14,
              )),
          if (_isFetchingRoute) ...[
            const SizedBox(width: 8),
            const SizedBox(
              height: 12,
              width: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.volunteerBlue),
            ),
          ],
        ] else
          const Text('Getting your location…',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }

  Widget _buildNoGpsBanner() {
    return Container(
      key: const ValueKey('nogps_banner'),
      color: Colors.orange.withValues(alpha: 0.10),
      padding: const EdgeInsets.all(10),
      child: const Row(children: [
        Icon(Icons.warning_amber, color: Colors.orange, size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'No GPS coordinates stored for this family. '
            'Capture the family location in the household form first.',
            style: TextStyle(fontSize: 12, color: Colors.orange),
          ),
        ),
      ]),
    );
  }

  Widget _buildNoGpsPlaceholder() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.location_off,
            size: 64, color: Colors.grey.withValues(alpha: 0.50)),
        const SizedBox(height: 16),
        const Text('No GPS Data Available',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.grey)),
        const SizedBox(height: 8),
        const Text('The family location was not captured.\nNavigation is disabled.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey)),
      ]),
    );
  }

  Widget _buildMapControls(bool isDark) {
    return Positioned(
      right: 12,
      bottom: 14,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _MapFab(
            icon: _mapStyle.icon,
            tooltip: 'Map Style',
            onTap: _showMapStylePicker,
            isDark: isDark),
        const SizedBox(height: 6),
        _MapFab(
            icon: Icons.add, tooltip: 'Zoom In', onTap: _zoomIn, isDark: isDark),
        const SizedBox(height: 4),
        _MapFab(
            icon: Icons.remove,
            tooltip: 'Zoom Out',
            onTap: _zoomOut,
            isDark: isDark),
        const SizedBox(height: 6),
        _MapFab(
            icon: Icons.explore_outlined,
            tooltip: 'Reset North',
            onTap: _resetNorth,
            isDark: isDark),
        const SizedBox(height: 6),
        _MapFab(
            icon: Icons.my_location,
            tooltip: 'My Location',
            onTap: _centerOnMe,
            active: !_centeredOnFamily && _myPosition != null,
            isDark: isDark),
        const SizedBox(height: 6),
        _MapFab(
            icon: Icons.home_outlined,
            tooltip: 'Family Location',
            onTap: _centerOnFamily,
            active: _centeredOnFamily,
            isDark: isDark),
      ]),
    );
  }

  Widget _buildBottomBar(bool isDark, LatLng? familyLatLng) {
    final canStart =
        familyLatLng != null && _myPosition != null && !_isFetchingRoute;

    return Container(
      color: isDark ? const Color(0xFF121212) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _isNavigating
              ? _stopNavigation
              : (canStart ? _startNavigation : null),
          icon: Icon(
            _isFetchingRoute
                ? Icons.hourglass_top
                : (_isNavigating ? Icons.stop_circle_outlined : Icons.navigation),
            size: 18,
          ),
          label: Text(
            _isNavigating
                ? 'Stop Navigation'
                : _isFetchingRoute
                    ? 'Loading Route…'
                    : _myPosition == null
                        ? 'Waiting for GPS…'
                        : familyLatLng == null
                            ? 'No GPS Location'
                            : 'Start Navigation',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _isNavigating ? Colors.red.shade600 : AppColors.volunteerBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[300],
            disabledForegroundColor: Colors.grey[600],
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
        ),
      ),
    );
  }
}

// ─── Private Widget: Advanced Turn Banner ────────────────────────────────────

class _NavTurnBanner extends StatelessWidget {
  final NavStep currentStep;
  final NavStep? nextStep;
  final double distToTurn;
  final double? remainingDistMeters;
  final double? remainingSeconds;
  final double? speedKmh;
  final VoidCallback onStop;
  final String Function(double) fmtDist;
  final String Function(double) fmtDur;

  const _NavTurnBanner({
    super.key,
    required this.currentStep,
    this.nextStep,
    required this.distToTurn,
    this.remainingDistMeters,
    this.remainingSeconds,
    this.speedKmh,
    required this.onStop,
    required this.fmtDist,
    required this.fmtDur,
  });

  @override
  Widget build(BuildContext context) {
    final speed = speedKmh ?? 0;
    return Container(
      color: const Color(0xFF1B5E20),
      child: SafeArea(
        bottom: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Main row ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Maneuver icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_turnIcon(currentStep),
                      color: _turnColor(currentStep), size: 32),
                ),
                const SizedBox(width: 14),
                // Distance to turn + instruction
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmtDist(distToTurn),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          )),
                      const SizedBox(height: 3),
                      Text(currentStep.instruction,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Speed-tinted speedometer ring
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _speedColor(speed),
                      width: 2.5,
                    ),
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        speed.toStringAsFixed(0),
                        style: TextStyle(
                          color: _speedColor(speed),
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                      Text('km/h',
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Stop (X) button
                GestureDetector(
                  onTap: onStop,
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white12),

          // ── Next step + ETA row ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              if (nextStep != null) ...[
                Icon(_turnIcon(nextStep!), color: Colors.white38, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Then: ${nextStep!.instruction}',
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                const Spacer(),
              if (remainingSeconds != null && remainingDistMeters != null) ...[
                const Icon(Icons.schedule_outlined,
                    color: Colors.white54, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${fmtDur(remainingSeconds!)} · ${fmtDist(remainingDistMeters!)}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  // Speed-adaptive tint: green → yellow → red
  static Color _speedColor(double kmh) {
    if (kmh < 50) return Colors.greenAccent;
    if (kmh < 80) return Colors.yellowAccent;
    return Colors.redAccent;
  }

  static IconData _turnIcon(NavStep step) {
    if (step.type == 'arrive') return Icons.flag_rounded;
    if (step.type == 'depart') return Icons.near_me_outlined;
    if (step.type == 'roundabout' || step.type == 'rotary') {
      return Icons.rotate_right;
    }
    final mod = step.modifier.toLowerCase();
    if (mod.contains('sharp left')) return Icons.turn_sharp_left;
    if (mod.contains('sharp right')) return Icons.turn_sharp_right;
    if (mod.contains('slight left')) return Icons.turn_slight_left;
    if (mod.contains('slight right')) return Icons.turn_slight_right;
    if (mod.contains('left')) return Icons.turn_left;
    if (mod.contains('right')) return Icons.turn_right;
    if (mod.contains('u-turn') || mod.contains('uturn')) {
      return Icons.u_turn_left;
    }
    return Icons.straight;
  }

  static Color _turnColor(NavStep step) =>
      step.type == 'arrive' ? Colors.greenAccent : Colors.white;
}

// ─── Private Widget: Animated Heading Arrow + Pulsing Ring ───────────────────

class _YouMarker extends StatelessWidget {
  final double heading; // 0–360°, 0 = north
  final bool isNavigating;
  final Animation<double> pulse; // 0.0→1.0 repeating

  const _YouMarker({
    required this.heading,
    required this.isNavigating,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    final markerColor = isNavigating ? Colors.blue : Colors.green;

    return Stack(
      alignment: Alignment.center,
      children: [
        // ── Pulsing outer accuracy ring ──────────────────────────────────
        // Uses AnimatedBuilder so it repaints at animation FPS without
        // triggering a full widget-tree setState.
        AnimatedBuilder(
          animation: pulse,
          builder: (context, _) {
            final t = pulse.value;
            // Scale: 1.0 → 2.0; Opacity: 0.5 → 0.0
            final scale = 1.0 + t * 1.0;
            final opacity = (0.5 * (1.0 - t)).clamp(0.0, 1.0);
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: markerColor.withValues(alpha: opacity),
                    width: 2,
                  ),
                ),
              ),
            );
          },
        ),

        // ── Static inner ring ────────────────────────────────────────────
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: markerColor.withValues(alpha: 0.18),
            border: Border.all(
              color: markerColor.withValues(alpha: 0.50),
              width: 1.5,
            ),
          ),
        ),

        // ── Heading arrow (smooth AnimatedRotation) ──────────────────────
        // AnimatedRotation transitions between compass angles at 300 ms,
        // giving a fluid needle-like rotation instead of a jump.
        AnimatedRotation(
          turns: heading / 360.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: Icon(
            Icons.navigation_rounded,
            color: markerColor,
            size: 26,
          ),
        ),
      ],
    );
  }
}

// ─── Private Widget: Family Destination Marker ────────────────────────────────

class _FamilyMarker extends StatelessWidget {
  final bool verified;
  const _FamilyMarker({required this.verified});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.volunteerBlue,
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: AppColors.volunteerBlue.withValues(alpha: 0.40),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (verified) ...[
            const Icon(Icons.verified_rounded, size: 10, color: Colors.white),
            const SizedBox(width: 3),
          ],
          const Text('Family',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              )),
        ]),
      ),
      const Icon(Icons.location_pin, color: AppColors.volunteerBlue, size: 36),
    ]);
  }
}

// ─── Private Widget: Animated Route Progress Bar ─────────────────────────────

/// A slim 6 px gradient bar that fills from left to right as the user
/// progresses along the route. Uses [AnimatedContainer] for smooth width
/// interpolation between step changes.
class _RouteProgressBar extends StatelessWidget {
  final double fraction; // 0.0–1.0

  const _RouteProgressBar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: Stack(children: [
        // Track
        Container(color: Colors.white.withValues(alpha: 0.25)),
        // Fill
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction.clamp(0.0, 1.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF81C784), Color(0xFF2E7D32)],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Private Widget: GPS Chip ────────────────────────────────────────────────

class _GpsChip extends StatelessWidget {
  final bool verified;
  const _GpsChip({required this.verified});

  @override
  Widget build(BuildContext context) {
    final color = verified ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(verified ? Icons.verified_rounded : Icons.location_on,
            size: 12, color: color),
        const SizedBox(width: 4),
        Text(verified ? 'Verified GPS' : 'Unverified GPS',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

// ─── Private Widget: Map FAB ─────────────────────────────────────────────────

class _MapFab extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool isDark;

  const _MapFab({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Material(
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
            child: Icon(icon, size: 22,
                color: active
                    ? AppColors.volunteerBlue
                    : (isDark ? Colors.grey[300] : Colors.grey[700])),
          ),
        ),
      ),
    );
  }
}
