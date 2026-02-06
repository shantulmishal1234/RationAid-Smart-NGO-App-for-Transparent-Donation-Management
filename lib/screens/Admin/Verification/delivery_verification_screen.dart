import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';

class DeliveryVerificationScreen extends StatefulWidget {
  const DeliveryVerificationScreen({super.key});

  @override
  State<DeliveryVerificationScreen> createState() =>
      _DeliveryVerificationScreenState();
}

class _DeliveryVerificationScreenState
    extends State<DeliveryVerificationScreen> {
  bool _isProcessing = false;
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  /// Show dialog to upload proof and confirm delivery
  Future<void> _confirmDelivery(Family family) async {
    _imageFile = null; // Reset

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Confirm Delivery'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Upload proof of delivery for ${family.city}, ${family.area}.',
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () async {
                    final picked = await _picker.pickImage(
                      source: ImageSource.camera,
                    );
                    if (picked != null) {
                      setState(() => _imageFile = File(picked.path));
                    }
                  },
                  child: Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _imageFile != null
                        ? Image.file(_imageFile!, fit: BoxFit.cover)
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt,
                                size: 40,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text('Tap to take photo'),
                            ],
                          ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _imageFile == null
                    ? null
                    : () {
                        Navigator.pop(context);
                        _processDelivery(family, _imageFile!);
                      },
                child: const Text('Confirm Delivery'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processDelivery(Family family, File proofImage) async {
    setState(() => _isProcessing = true);

    try {
      // 1. Upload Image
      final url = await CloudinaryService.uploadImage(proofImage);
      if (url == null) throw Exception('Image upload failed');

      // 2. Update Firestore
      final user = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance
          .collection('families')
          .doc(family.id)
          .update({
            'fulfillmentStatus': 'delivered',
            'deliveredBy': user?.uid,
            'deliveredByName': user?.displayName ?? user?.email ?? 'Staff',
            'deliveredAt': FieldValue.serverTimestamp(),
            'deliveryProof': url,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // 3. Log Audit
      await AuditService.logFamilyAction(
        action: 'Delivery Verified',
        familyId: family.id,
        familyName: 'Family of ${family.familySize}',
        details: 'Proof uploaded. Delivered by ${user?.email}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery confirmed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Delivery Verification',
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('families')
                  .where('status', isEqualTo: 'accepted')
                  .where('fulfillmentStatus', isEqualTo: 'purchase_approved')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.local_shipping_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No deliveries pending',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final family = Family.fromFirestore(doc);
                    return _buildDeliveryCard(family);
                  },
                );
              },
            ),
    );
  }

  Widget _buildDeliveryCard(Family family) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${family.address}, ${family.area}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row('Assigned Pack', family.assignedPackName ?? 'Standard Pack'),
            _row('Recipient', family.phone ?? 'No Phone'),

            const Divider(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirmDelivery(family),
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('Verify Delivery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
