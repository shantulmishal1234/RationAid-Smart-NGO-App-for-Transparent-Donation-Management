import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

/// Location Picker Widget
/// Uses OpenStreetMap for interactive map with pin-drop functionality
class LocationPicker extends StatefulWidget {
  final LatLng? initialLocation;
  final Function(LatLng location, String address) onLocationSelected;

  const LocationPicker({
    super.key,
    this.initialLocation,
    required this.onLocationSelected,
  });

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  late MapController _mapController;
  LatLng? _selectedLocation;
  bool _isLoadingCurrentLocation = false;
  String _selectedAddress = '';

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedLocation =
        widget.initialLocation ??
        const LatLng(33.6844, 73.0479); // Default: Islamabad, Pakistan
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Get current GPS location
  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingCurrentLocation = true);

    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied');
      }

      // Get position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final newLocation = LatLng(position.latitude, position.longitude);

      setState(() {
        _selectedLocation = newLocation;
        _isLoadingCurrentLocation = false;
      });

      // Move map to new location
      _mapController.move(newLocation, 15.0);

      // Get address (reverse geocoding would be done here - simplified for now)
      _selectedAddress =
          'Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}';
    } catch (e) {
      setState(() => _isLoadingCurrentLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Select Family Location',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Map
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _selectedLocation!,
                      initialZoom: 13.0,
                      onTap: (tapPosition, point) {
                        setState(() {
                          _selectedLocation = point;
                          _selectedAddress =
                              'Lat: ${point.latitude.toStringAsFixed(6)}, Lng: ${point.longitude.toStringAsFixed(6)}';
                        });
                      },
                    ),
                    children: [
                      // OpenStreetMap Tile Layer
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.rationaid.app',
                      ),
                      // Marker Layer
                      if (_selectedLocation != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedLocation!,
                              width: 60,
                              height: 60,
                              child: const Icon(
                                Icons.location_pin,
                                size: 50,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  // GPS Button
                  Positioned(
                    right: 16,
                    top: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'gps',
                      onPressed: _isLoadingCurrentLocation
                          ? null
                          : _getCurrentLocation,
                      backgroundColor: Colors.white,
                      child: _isLoadingCurrentLocation
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location, color: Colors.blue),
                    ),
                  ),

                  // Zoom Controls
                  Positioned(
                    right: 16,
                    bottom: 100,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'zoom_in',
                          onPressed: () {
                            final currentZoom = _mapController.camera.zoom;
                            _mapController.move(
                              _mapController.camera.center,
                              currentZoom + 1,
                            );
                          },
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.add, color: Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'zoom_out',
                          onPressed: () {
                            final currentZoom = _mapController.camera.zoom;
                            _mapController.move(
                              _mapController.camera.center,
                              currentZoom - 1,
                            );
                          },
                          backgroundColor: Colors.white,
                          child: const Icon(
                            Icons.remove,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Location Info & Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Colors.grey[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedAddress.isEmpty
                              ? 'Tap on map to select location'
                              : _selectedAddress,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _selectedLocation == null
                              ? null
                              : () {
                                  widget.onLocationSelected(
                                    _selectedLocation!,
                                    _selectedAddress,
                                  );
                                  Navigator.pop(context);
                                },
                          icon: const Icon(Icons.check),
                          label: const Text('Confirm Location'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
