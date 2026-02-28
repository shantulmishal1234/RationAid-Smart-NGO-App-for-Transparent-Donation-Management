import 'dart:io';

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
  bool _isUploading = false;
  bool _isGettingLocation = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  Future<void> _getLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied');
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) setState(() => _position = pos);
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

  Future<void> _takePhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  Future<void> _pickFromGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked != null) setState(() => _photo = File(picked.path));
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

    setState(() => _isUploading = true);

    try {
      await DeliveryService.submitProofOfDelivery(
        assignmentId: widget.assignment.id,
        familyId: widget.assignment.familyId,
        proofPhoto: _photo!,
        lat: _position?.latitude,
        lng: _position?.longitude,
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
      // Save offline for ANY failure (network, Cloudinary, Firestore timeout, etc.)
      // The user can always manually choose to retry online
      await _saveOffline();
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _saveOffline() async {
    await DeliveryService.saveProofOffline(
      assignmentId: widget.assignment.id,
      familyId: widget.assignment.familyId,
      localPhotoPath: _photo!.path,
      lat: _position?.latitude,
      lng: _position?.longitude,
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
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: const Text('Retake'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.volunteerBlue,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library, size: 16),
                    label: const Text('Gallery'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // GPS Section
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _position != null
                    ? Colors.green.withValues(alpha: 0.06)
                    : Colors.orange.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _position != null
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _position != null
                        ? Icons.gps_fixed
                        : (_isGettingLocation
                              ? Icons.gps_not_fixed
                              : Icons.gps_off),
                    color: _position != null ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _isGettingLocation
                        ? const Text(
                            'Getting GPS location...',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          )
                        : _position != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'GPS Location Captured ✅',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '${_position!.latitude.toStringAsFixed(5)}, ${_position!.longitude.toStringAsFixed(5)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'GPS not captured — location will not be recorded',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _getLocation,
                                child: const Text(
                                  'Retry',
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
            ),

            const SizedBox(height: 32),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _submit,
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
                  _isUploading ? 'Submitting...' : 'Submit Proof of Delivery',
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
            ),

            const SizedBox(height: 12),

            // Offline save button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: (_photo == null || _isUploading)
                    ? null
                    : _saveOffline,
                icon: const Icon(Icons.save_alt, size: 18),
                label: const Text('Save Offline (Sync Later)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepOrange,
                  side: const BorderSide(color: Colors.deepOrange),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
