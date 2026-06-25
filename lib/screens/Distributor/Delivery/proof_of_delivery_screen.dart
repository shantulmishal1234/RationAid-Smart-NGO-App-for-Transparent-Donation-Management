import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

class ProofOfDeliveryScreen extends StatefulWidget {
  final DeliveryAssignment assignment;

  const ProofOfDeliveryScreen({super.key, required this.assignment});

  @override
  State<ProofOfDeliveryScreen> createState() => _ProofOfDeliveryScreenState();
}

class _ProofOfDeliveryScreenState extends State<ProofOfDeliveryScreen> {
  File? _photo;
  Position? _position;
  double? _distanceInMeters;
  StreamSubscription<Position>? _posSub;
  bool _isUploading = false;
  bool _isGettingLocation = false;
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _startLocationStream();
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _updateConnectionStatus(result);
    _connSub = Connectivity().onConnectivityChanged.listen(
      _updateConnectionStatus,
    );
  }

  void _updateConnectionStatus(List<ConnectivityResult> result) {
    if (!mounted) return;
    setState(() {
      _isOnline = !result.contains(ConnectivityResult.none);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _startLocationStream() async {
    setState(() => _isGettingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied');
      }

      // Get initial quick position
      final initPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _updatePosition(initPos);

      // Start stream for live updates (e.g., if they are walking towards the door)
      _posSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 2,
            ),
          ).listen((pos) {
            _updatePosition(pos);
          });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location: $e — GPS will not be included'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  void _updatePosition(Position pos) {
    if (!mounted) return;
    setState(() {
      _position = pos;
      final famLat = widget.assignment.familyGeoLat;
      final famLng = widget.assignment.familyGeoLng;

      if (famLat != null && famLng != null && famLat != 0.0 && famLng != 0.0) {
        _distanceInMeters = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          famLat,
          famLng,
        );
      }
    });
  }

  Future<void> _takePhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  bool _validateGeoFence() {
    if (_position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GPS Location is strictly required. Please wait for GPS lock.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    if (_distanceInMeters == null) {
      // If distance couldn't be calculated because family coords are missing,
      // we might allow it, but generally we want to track it.
      return true;
    }

    if (_distanceInMeters! > 50.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ You are ${_distanceInMeters!.toStringAsFixed(0)}m away. You must be within 50m of the family location to deliver.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return false;
    }

    return true;
  }

  Future<void> _submit() async {
    if (_photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take or select a photo first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_validateGeoFence()) return;

    setState(() => _isUploading = true);

    try {
      // 1. Fetch donor IDs linked to this family's verified/active donations
      final donorSnap = await FirebaseFirestore.instance
          .collection('donations')
          .where('familyId', isEqualTo: widget.assignment.familyId)
          .where(
            'status',
            whereIn: ['verified', 'in_process', 'out_for_delivery'],
          )
          .get();

      final donorIds = donorSnap.docs
          .map((d) => d.data()['donorId'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      // 2. Submit the proof
      await DeliveryService.submitProofOfDelivery(
        assignmentId: widget.assignment.id,
        familyId: widget.assignment.familyId,
        proofPhoto: _photo!,
        lat: _position?.latitude,
        lng: _position?.longitude,
        donorIds:
            donorIds, // Fix #1: Now donors will actually get the notification!
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Delivery proof submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      final isNetworkError =
          errStr.contains('socket') ||
          errStr.contains('network') ||
          errStr.contains('host lookup') ||
          errStr.contains('timeout') ||
          errStr.contains('offline');

      if (isNetworkError) {
        // Save offline ONLY for connectivity/network related failures
        await _saveOffline();
      } else {
        // Rethrow data/logic errors so the user knows what went wrong and it doesn't get stuck in the offline queue
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to submit proof: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _saveOffline() async {
    if (!_validateGeoFence()) return;

    // Attempt to grab donor IDs for offline sync later (fails silently if fully offline)
    List<String> cachedDonorIds = [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('donations')
          .where('familyId', isEqualTo: widget.assignment.familyId)
          .where(
            'status',
            whereIn: ['verified', 'in_process', 'out_for_delivery'],
          )
          .get(const GetOptions(source: Source.cache));

      cachedDonorIds = snap.docs
          .map((d) => d.data()['donorId'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
    } catch (_) {
      // Ignore if cache read fails
    }

    await DeliveryService.saveProofOffline(
      assignmentId: widget.assignment.id,
      familyId: widget.assignment.familyId,
      localPhotoPath: _photo!.path,
      lat: _position?.latitude,
      lng: _position?.longitude,
      donorIds: cachedDonorIds,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '📴 Saved offline — will sync automatically when connected',
          ),
          backgroundColor: Colors.deepOrange,
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Proof of Delivery',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.volunteerBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Family info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.volunteerBlue.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: AppColors.volunteerBlue,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.assignment.familyArea}, ${widget.assignment.familyCity}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Photo section
            Text(
              'Delivery Photo *',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Take a photo of the delivered items at the family\'s location',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 12),

            // Photo preview / capture
            GestureDetector(
              onTap: _takePhoto,
              child: Container(
                height: 240,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2E) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _photo != null
                        ? Colors.green.withValues(alpha: 0.5)
                        : Colors.grey.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: _photo != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(_photo!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt,
                            size: 52,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Tap to take photo',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            if (_photo != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _takePhoto,
                icon: const Icon(Icons.camera_alt, size: 16),
                label: const Text('Retake Photo'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.volunteerBlue,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // GPS Section
            Builder(
              builder: (context) {
                final bool hasFamilyCoords =
                    widget.assignment.familyGeoLat != null &&
                    widget.assignment.familyGeoLat != 0.0;
                final bool isGeoFenceValid =
                    _distanceInMeters != null && _distanceInMeters! <= 50.0;
                final bool outOfRangeAndHasCoords =
                    hasFamilyCoords &&
                    _distanceInMeters != null &&
                    _distanceInMeters! > 50.0;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _position != null
                        ? (outOfRangeAndHasCoords
                              ? Colors.red.withValues(alpha: 0.06)
                              : Colors.green.withValues(alpha: 0.06))
                        : Colors.orange.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _position != null
                          ? (outOfRangeAndHasCoords
                                ? Colors.red.withValues(alpha: 0.3)
                                : Colors.green.withValues(alpha: 0.3))
                          : Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _position != null
                            ? (outOfRangeAndHasCoords
                                  ? Icons.gps_off
                                  : Icons.gps_fixed)
                            : (_isGettingLocation
                                  ? Icons.gps_not_fixed
                                  : Icons.gps_off),
                        color: _position != null
                            ? (outOfRangeAndHasCoords
                                  ? Colors.red
                                  : Colors.green)
                            : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _isGettingLocation
                            ? const Text(
                                'Getting Live GPS location...',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              )
                            : _position != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!hasFamilyCoords)
                                    const Text(
                                      'GPS Ready (Family coords missing) ✅',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green,
                                        fontSize: 13,
                                      ),
                                    )
                                  else if (isGeoFenceValid)
                                    Text(
                                      'In Range ✅ (${_distanceInMeters!.toStringAsFixed(0)}m away)',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green,
                                        fontSize: 13,
                                      ),
                                    )
                                  else
                                    Text(
                                      'Out of Range ❌ (${_distanceInMeters!.toStringAsFixed(0)}m away)',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.red,
                                        fontSize: 13,
                                      ),
                                    ),
                                  const SizedBox(height: 3),
                                  Text(
                                    outOfRangeAndHasCoords
                                        ? 'Move within 50 meters of the family to submit.'
                                        : '${_position!.latitude.toStringAsFixed(5)}, ${_position!.longitude.toStringAsFixed(5)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: outOfRangeAndHasCoords
                                          ? Colors.red.withValues(alpha: 0.8)
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'GPS required to enforce 50m delivery limit',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _startLocationStream,
                                    child: const Text(
                                      'Acquire GPS',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Dynamic Submit / Offline button
            Builder(
              builder: (context) {
                final bool hasFamilyCoords =
                    widget.assignment.familyGeoLat != null &&
                    widget.assignment.familyGeoLat != 0.0;
                final bool outOfRangeAndHasCoords =
                    hasFamilyCoords &&
                    _distanceInMeters != null &&
                    _distanceInMeters! > 50.0;
                final bool canSubmit =
                    _photo != null && !outOfRangeAndHasCoords && !_isUploading;

                if (_isOnline) {
                  return SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: canSubmit ? _submit : null,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(
                        _isUploading
                            ? 'Submitting...'
                            : 'Submit Proof of Delivery',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  );
                } else {
                  return SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: canSubmit ? _saveOffline : null,
                      icon: const Icon(Icons.save_alt),
                      label: const Text(
                        'Save Proof Securely (Offline Sync)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
