import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/theme/app_colors.dart';

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

class _DeliveryMapScreenState extends State<DeliveryMapScreen> {
  late final MapController _mapController;
  LatLng? _myPosition;
  StreamSubscription<Position>? _positionSub;
  bool _centeredOnFamily = true;
  double? _distanceMeters;

  DeliveryAssignment get a => widget.assignment;

  LatLng? get _familyLatLng {
    if (a.familyGeoLat == null || a.familyGeoLng == null) return null;
    return LatLng(a.familyGeoLat!, a.familyGeoLng!);
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _startTracking();
  }

  @override
  void dispose() {
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
            distanceFilter: 10, // update every 10 metres
          ),
        ).listen((pos) {
          if (!mounted) return;
          final myLatLng = LatLng(pos.latitude, pos.longitude);
          setState(() {
            _myPosition = myLatLng;
            if (_familyLatLng != null) {
              _distanceMeters = _haversine(myLatLng, _familyLatLng!);
            }
          });
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

  void _centerOnFamily() {
    if (_familyLatLng != null) {
      _mapController.move(_familyLatLng!, 16);
      setState(() => _centeredOnFamily = true);
    }
  }

  void _centerOnMe() {
    if (_myPosition != null) {
      _mapController.move(_myPosition!, 16);
      setState(() => _centeredOnFamily = false);
    }
  }

  void _showNavigateSheet() {
    if (_familyLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No GPS coordinates recorded for this family yet.'),
        ),
      );
      return;
    }

    final lat = _familyLatLng!.latitude;
    final lng = _familyLatLng!.longitude;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Navigate To Delivery Location',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  '${a.familyArea}, ${a.familyCity}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
                _navButton(
                  icon: Icons.map,
                  label: 'Google Maps',
                  color: const Color(0xFF4285F4),
                  url:
                      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
                ),
                const SizedBox(height: 10),
                _navButton(
                  icon: Icons.navigation,
                  label: 'Waze',
                  color: const Color(0xFF33CCFF),
                  url: 'https://www.waze.com/ul?ll=$lat,$lng&navigate=yes',
                ),
                const SizedBox(height: 10),
                _navButton(
                  icon: Icons.language,
                  label: 'OpenStreetMap (Browser)',
                  color: const Color(0xFF7EBC6F),
                  url:
                      'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng&zoom=16',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _navButton({
    required IconData icon,
    required String label,
    required Color color,
    required String url,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: () async {
          Navigator.pop(context);
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Cannot open $label')));
            }
          }
        },
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
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
      appBar: AppBar(
        title: Text(
          '${a.familyArea} — Navigation',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.volunteerBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (familyLatLng != null)
            IconButton(
              icon: const Icon(Icons.navigation),
              tooltip: 'Navigate',
              onPressed: _showNavigateSheet,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Distance banner ────────────────────────────────────────────
          if (familyLatLng != null)
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
                          ? Colors.green.withOpacity(0.15)
                          : Colors.orange.withOpacity(0.15),
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
                  if (_distanceMeters != null) ...[
                    const Icon(
                      Icons.straighten,
                      size: 16,
                      color: AppColors.volunteerBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDistance(_distanceMeters!),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.volunteerBlue,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'away',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
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
              color: Colors.orange.withOpacity(0.1),
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
            child: Stack(
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

                    // Markers layer
                    MarkerLayer(
                      markers: [
                        // Family destination pin (blue)
                        if (familyLatLng != null)
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
                                            .withOpacity(0.4),
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
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.green.withOpacity(0.4),
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
                    onPressed: _showNavigateSheet,
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text(
                      'Navigate',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.volunteerBlue,
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
