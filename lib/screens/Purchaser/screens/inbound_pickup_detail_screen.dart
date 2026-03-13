import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ration_aid/models/inbound_pickup_model.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

/// Purchaser's Inbound Pickup Detail Screen
///
/// A Purchaser taps an open pickup task, reviews donor details,
/// optionally accepts the task, goes to the donor's address,
/// takes a proof photo, adds a note, and marks as collected.
///
/// On "Mark as Collected":
///   1. Uploads proof photo to Cloudinary
///   2. Sets inbound_pickups status → completed
///   3. Sets warehouse_stock status → received
///   4. Sends notification to Admin
class InboundPickupDetailScreen extends StatefulWidget {
  final InboundPickup pickup;
  const InboundPickupDetailScreen({super.key, required this.pickup});

  @override
  State<InboundPickupDetailScreen> createState() =>
      _InboundPickupDetailScreenState();
}

class _InboundPickupDetailScreenState extends State<InboundPickupDetailScreen> {
  final _db = FirebaseFirestore.instance;
  final _noteController = TextEditingController();
  final _picker = ImagePicker();

  File? _proofImage;
  bool _isUploading = false;
  bool _isAccepting = false;

  late InboundPickup _pickup;

  @override
  void initState() {
    super.initState();
    _pickup = widget.pickup;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get _isMyTask => _pickup.assignedTo == _currentUid;
  bool get _isOpen => _pickup.status == 'open';
  bool get _isInProgress => _pickup.status == 'in_progress';

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _acceptTask() async {
    setState(() => _isAccepting = true);
    try {
      await _db.collection('inbound_pickups').doc(_pickup.id).update({
        'status': 'in_progress',
        'assignedTo': _currentUid,
      });
      setState(() {
        _pickup = _pickup.copyWith(
          status: 'in_progress',
          assignedTo: _currentUid,
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Task accepted — head to the pickup address'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accepting task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt,
                color: AppColors.purchaserOrange,
              ),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: AppColors.purchaserOrange,
              ),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1200,
    );
    if (picked != null && mounted) {
      setState(() => _proofImage = File(picked.path));
    }
  }

  Future<void> _markCollected() async {
    if (_proofImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please take a proof photo before marking as collected',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _isUploading = true);
    try {
      // 1. Upload proof photo
      final proofUrl = await CloudinaryService.uploadImage(_proofImage!);

      // 2. Batch: complete the pickup task + mark warehouse batch as received
      final batch = _db.batch();

      final pickupRef = _db.collection('inbound_pickups').doc(_pickup.id);
      batch.update(pickupRef, {
        'status': 'completed',
        'pickupProofUrl': proofUrl,
        'proofUploadedAt': FieldValue.serverTimestamp(),
        if (_noteController.text.trim().isNotEmpty)
          'note': _noteController.text.trim(),
      });

      // 3. Also update the linked warehouse_stock document
      if (_pickup.batchId.isNotEmpty) {
        final stockRef = _db.collection('warehouse_stock').doc(_pickup.batchId);
        batch.update(stockRef, {
          'status': 'received',
          'pickupProofUrl': proofUrl,
          'receivedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '📦 Items marked as received and stored in warehouse!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _callDonor() async {
    final phone = _pickup.contactNumber.replaceAll(' ', '');
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback: copy to clipboard
      await Clipboard.setData(ClipboardData(text: phone));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone number copied to clipboard')),
        );
      }
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Pickup Task',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.purchaserOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status card
            _statusBanner(isDark),

            const SizedBox(height: 20),

            // Donor Info
            _sectionTitle('Donor Contact'),
            const SizedBox(height: 10),
            _contactCard(isDark),

            const SizedBox(height: 20),

            // Items to collect
            _sectionTitle('Items to Collect'),
            const SizedBox(height: 10),
            _itemsCard(theme, isDark),

            const SizedBox(height: 20),

            // Proof Photo (only shown when assigned)
            if (_isMyTask || _isInProgress) ...[
              _sectionTitle('Proof of Collection'),
              const SizedBox(height: 10),
              _proofSection(theme, isDark),
              const SizedBox(height: 20),

              // Notes (optional)
              _sectionTitle('Purchaser Note (Optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _noteController,
                maxLines: 3,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText:
                      'e.g., Rice bag was slightly less (~9kg instead of 10kg)',
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.4),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.purchaserOrange,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Mark as Collected CTA
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isUploading ? null : _markCollected,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline, size: 22),
                  label: Text(
                    _isUploading ? 'Uploading...' : 'Mark as Collected ✓',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],

            // Accept button (only for open tasks not yet assigned to me)
            if (_isOpen && !_isMyTask)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isAccepting ? null : _acceptTask,
                  icon: _isAccepting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.handshake_outlined, size: 22),
                  label: Text(
                    _isAccepting ? 'Accepting...' : 'Accept This Task',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purchaserOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ─── UI Sections ──────────────────────────────────────────────────────────

  Widget _statusBanner(bool isDark) {
    final Color bgColor;
    final IconData icon;
    final String label;

    if (_pickup.status == 'completed') {
      bgColor = Colors.green;
      icon = Icons.check_circle;
      label = 'Completed — Items in Warehouse';
    } else if (_isInProgress && _isMyTask) {
      bgColor = Colors.orange;
      icon = Icons.directions_walk;
      label = 'In Progress — Assigned to You';
    } else if (_isInProgress) {
      bgColor = Colors.orange;
      icon = Icons.pending;
      label = 'In Progress — Assigned to Another Purchaser';
    } else {
      bgColor = Colors.teal;
      icon = Icons.inbox;
      label = 'Open — Pickup Needed';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bgColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: bgColor, size: 22),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: bgColor,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          _infoRow(Icons.person_outline, 'Donor', _pickup.donorName),
          const Divider(height: 20),
          _infoRow(
            Icons.location_on_outlined,
            'Pickup Address',
            _pickup.pickupAddress,
          ),
          const Divider(height: 20),
          Row(
            children: [
              const Icon(Icons.phone_outlined, size: 18, color: Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Contact Number',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _pickup.contactNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _callDonor,
                icon: const Icon(Icons.call, size: 16),
                label: const Text('Call'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal,
                  side: const BorderSide(color: Colors.teal),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemsCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.purchaserOrange.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: _pickup.items.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: AppColors.purchaserOrange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.purchaserOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Qty: ${entry.value}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.purchaserOrange,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _proofSection(ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _proofImage != null
                ? Colors.green.withValues(alpha: 0.5)
                : AppColors.purchaserOrange.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: _proofImage != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.file(_proofImage!, fit: BoxFit.cover),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    size: 40,
                    color: AppColors.purchaserOrange.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Tap to take photo of collected items',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.purchaserOrange,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Camera or gallery',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value.isNotEmpty ? value : '—',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.purchaserOrange,
        letterSpacing: 0.4,
      ),
    );
  }
}
