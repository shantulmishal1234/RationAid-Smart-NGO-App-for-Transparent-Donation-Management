import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/services/notification_service.dart';

class DeliveryService {
  static final _db = FirebaseFirestore.instance;
  static const _collection = 'delivery_assignments';
  static const _offlineKey = 'pending_delivery_proofs';

  // ─── Create ────────────────────────────────────────────────────────────────

  /// Create a new delivery assignment (called by Admin when family is stocked)
  static Future<String> createAssignment({
    required String familyId,
    required String familyArea,
    required String familyCity,
    required String familyAddress,
    String? familyPhone,
    int familySize = 0,
    double? familyGeoLat,
    double? familyGeoLng,
    bool familyLocationVerified = false,
    String? assignedPackId,
    String? assignedPackName,
    Map<String, int> items = const {},
    String? distributorId,
    String? distributorName,
    String? procurementRequestId,
    DateTime? scheduledAt,
    String? adminNote,
  }) async {
    final now = DateTime.now();
    final ref = _db.collection(_collection).doc();

    final assignment = DeliveryAssignment(
      id: ref.id,
      familyId: familyId,
      familyArea: familyArea,
      familyCity: familyCity,
      familyAddress: familyAddress,
      familyPhone: familyPhone,
      familySize: familySize,
      familyGeoLat: familyGeoLat,
      familyGeoLng: familyGeoLng,
      familyLocationVerified: familyLocationVerified,
      assignedPackId: assignedPackId,
      assignedPackName: assignedPackName,
      items: items,
      assignedDistributorId: distributorId,
      assignedDistributorName: distributorName,
      status: DeliveryStatus.notStarted,
      scheduledAt: scheduledAt,
      procurementRequestId: procurementRequestId,
      adminNote: adminNote,
      createdAt: now,
      updatedAt: now,
    );

    await ref.set(assignment.toFirestore());

    // Notify the assigned distributor
    if (distributorId != null) {
      await NotificationService.sendToUser(
        userId: distributorId,
        title: 'New Delivery Assigned 🚚',
        body:
            'You have a new delivery to ${familyArea}, ${familyCity}. Tap to view details.',
        data: {'type': 'delivery_assigned', 'assignmentId': ref.id},
      );
    }

    await AuditService.logFamilyAction(
      action: 'Delivery assignment created',
      familyId: familyId,
      familyName: familyArea,
      details: 'Assigned to: ${distributorName ?? "Unassigned"}',
    );

    return ref.id;
  }

  // ─── Streams ───────────────────────────────────────────────────────────────

  /// Stream assignments for a specific distributor (live).
  /// NOTE: No .orderBy() here — combining where+orderBy on different fields
  /// requires a composite index. We sort client-side in AssignmentsSection._filter()
  static Stream<List<DeliveryAssignment>> streamAssignmentsByDistributor(
    String distributorId,
  ) {
    // Guard: never open a Firestore query with an empty distributorId —
    // that triggers an Internal Assertion error in the Firestore SDK.
    if (distributorId.isEmpty) return const Stream.empty();

    return _db
        .collection(_collection)
        .where('assignedDistributorId', isEqualTo: distributorId)
        .snapshots()
        .map((s) => s.docs.map(DeliveryAssignment.fromFirestore).toList());
  }

  /// Stream ALL assignments (Admin view)
  static Stream<List<DeliveryAssignment>> streamAllAssignments() {
    return _db
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(DeliveryAssignment.fromFirestore).toList());
  }

  /// Stream a single assignment (for real-time detail screen)
  static Stream<DeliveryAssignment?> streamAssignment(String id) {
    return _db
        .collection(_collection)
        .doc(id)
        .snapshots()
        .map((s) => s.exists ? DeliveryAssignment.fromFirestore(s) : null);
  }

  /// Stream the shared pool of UNASSIGNED ready deliveries.
  /// All distributors see these in real time — first to claim wins.
  static Stream<List<DeliveryAssignment>> streamAvailableAssignments() {
    return _db
        .collection(_collection)
        .where('status', isEqualTo: 'not_started')
        .where('assignedDistributorId', isNull: true)
        .snapshots()
        .map((s) => s.docs.map(DeliveryAssignment.fromFirestore).toList());
  }

  /// Atomically claim an unassigned delivery for a distributor.
  /// Uses a Firestore transaction so two distributors tapping at the same
  /// instant cannot both claim the same order — only one wins.
  ///
  /// Returns true if successfully claimed, false if already taken.
  static Future<bool> claimAssignment({
    required String assignmentId,
    required String distributorId,
    required String distributorName,
  }) async {
    final ref = _db.collection(_collection).doc(assignmentId);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw Exception('Assignment not found');

        final current = snap.data()!;
        // If someone else already claimed it, abort
        if (current['assignedDistributorId'] != null) {
          throw Exception('already_claimed');
        }

        tx.update(ref, {
          'assignedDistributorId': distributorId,
          'assignedDistributorName': distributorName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      await AuditService.logAction(
        action: 'claim_delivery',
        entityType: 'delivery_assignment',
        entityId: assignmentId,
        details: '$distributorName claimed the delivery',
      );
      return true;
    } catch (e) {
      if (e.toString().contains('already_claimed')) return false;
      rethrow;
    }
  }

  /// Release a claimed delivery back to the pool (before pick-up only).
  /// A distributor can release if they cannot do it; admin can also force-release.
  static Future<void> releaseAssignment({
    required String assignmentId,
    required String releasedByName,
  }) async {
    await _db.collection(_collection).doc(assignmentId).update({
      'assignedDistributorId': null,
      'assignedDistributorName': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await AuditService.logAction(
      action: 'release_delivery',
      entityType: 'delivery_assignment',
      entityId: assignmentId,
      details: '$releasedByName released the delivery back to the pool',
    );
  }

  // ─── Lifecycle Transitions ─────────────────────────────────────────────────

  /// Move assignment to Picked Up
  static Future<void> markPickedUp(String assignmentId) async {
    await _db.collection(_collection).doc(assignmentId).update({
      'status': DeliveryStatus.pickedUp.toFirestore(),
      'pickedUpAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Move assignment to In Transit
  static Future<void> markInTransit(String assignmentId) async {
    await _db.collection(_collection).doc(assignmentId).update({
      'status': DeliveryStatus.inTransit.toFirestore(),
      'inTransitAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Proof of Delivery ─────────────────────────────────────────────────────

  /// Submit proof of delivery: upload photo + save GPS
  static Future<void> submitProofOfDelivery({
    required String assignmentId,
    required String familyId,
    required File proofPhoto,
    double? lat,
    double? lng,
    String? reverseGeocodedAddress,
    List<String> donorIds = const [],
  }) async {
    // 1. Upload photo to Cloudinary
    final photoUrl = await CloudinaryService.uploadImage(proofPhoto);
    if (photoUrl == null) throw Exception('Failed to upload proof photo');

    final now = DateTime.now();

    // 2. Update delivery assignment
    await _db.collection(_collection).doc(assignmentId).update({
      'status': DeliveryStatus.delivered.toFirestore(),
      'deliveredAt': Timestamp.fromDate(now),
      'proofPhotoUrl': photoUrl,
      'proofGeoLat': lat,
      'proofGeoLng': lng,
      'proofTimestamp': Timestamp.fromDate(now),
      'proofAddress': reverseGeocodedAddress,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3. Update family fulfillment status
    await _db.collection('families').doc(familyId).update({
      'fulfillmentStatus': 'delivered',
      'deliveredAt': Timestamp.fromDate(now),
      'deliveryProof': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 4. Notify admin for verification
    await NotificationService.sendToRole(
      role: 'admin',
      title: 'Delivery Proof Submitted 📦',
      body: 'A delivery proof has been submitted and needs your verification.',
      data: {'type': 'delivery_proof_submitted', 'assignmentId': assignmentId},
    );

    // 5. Notify donors
    for (final donorId in donorIds) {
      await NotificationService.sendToUser(
        userId: donorId,
        title: 'Your Donation Reached the Family! ❤️',
        body:
            'The items you donated have been delivered to the family. Thank you!',
        data: {'type': 'donation_delivered', 'assignmentId': assignmentId},
      );
    }

    await AuditService.logFamilyAction(
      action: 'Delivery proof submitted',
      familyId: familyId,
      familyName: 'Family',
      details: 'Proof photo uploaded. GPS: ${lat ?? "N/A"}, ${lng ?? "N/A"}',
    );
  }

  // ─── Offline Proof Queue ───────────────────────────────────────────────────

  /// Save proof locally when offline
  static Future<void> saveProofOffline({
    required String assignmentId,
    required String familyId,
    required String localPhotoPath,
    double? lat,
    double? lng,
    String? reverseGeocodedAddress,
    List<String> donorIds = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_offlineKey) ?? [];

    final entry = jsonEncode({
      'assignmentId': assignmentId,
      'familyId': familyId,
      'localPhotoPath': localPhotoPath,
      'lat': lat,
      'lng': lng,
      'reverseGeocodedAddress': reverseGeocodedAddress,
      'donorIds': donorIds,
      'savedAt': DateTime.now().toIso8601String(),
    });

    existing.add(entry);
    await prefs.setStringList(_offlineKey, existing);
  }

  /// Sync all pending offline proofs (call on app start/resume)
  static Future<int> syncOfflineProofs() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_offlineKey) ?? [];
    if (pending.isEmpty) return 0;

    int synced = 0;
    final remaining = <String>[];

    for (final raw in pending) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final file = File(data['localPhotoPath'] as String);

        if (!file.existsSync()) {
          // File no longer exists, skip
          continue;
        }

        await submitProofOfDelivery(
          assignmentId: data['assignmentId'] as String,
          familyId: data['familyId'] as String,
          proofPhoto: file,
          lat: (data['lat'] as num?)?.toDouble(),
          lng: (data['lng'] as num?)?.toDouble(),
          reverseGeocodedAddress: data['reverseGeocodedAddress'] as String?,
          donorIds: data['donorIds'] != null
              ? List<String>.from(data['donorIds'] as List)
              : [],
        );
        synced++;
      } catch (_) {
        // Keep failed entries for retry
        remaining.add(raw);
      }
    }

    await prefs.setStringList(_offlineKey, remaining);
    return synced;
  }

  /// Check how many offline proofs are pending
  static Future<int> getPendingOfflineCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_offlineKey) ?? []).length;
  }

  // ─── Failure Reporting ─────────────────────────────────────────────────────

  static Future<void> reportFailure({
    required String assignmentId,
    required String familyId,
    required DeliveryFailureReason reason,
    String notes = '',
  }) async {
    await _db.collection(_collection).doc(assignmentId).update({
      'status': DeliveryStatus.failed.toFirestore(),
      'failedAt': FieldValue.serverTimestamp(),
      'failureReason': reason.toFirestore(),
      'failureNotes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Notify admin
    await NotificationService.sendToRole(
      role: 'admin',
      title: 'Delivery Failed ⚠️',
      body: 'Delivery failed: ${reason.displayName}. Manual review required.',
      data: {
        'type': 'delivery_failed',
        'assignmentId': assignmentId,
        'reason': reason.toFirestore(),
      },
    );

    await AuditService.logFamilyAction(
      action: 'Delivery failed',
      familyId: familyId,
      familyName: 'Assignment $assignmentId',
      details: 'Reason: ${reason.displayName}. Notes: $notes',
    );
  }

  // ─── Admin Actions ─────────────────────────────────────────────────────────

  /// Admin verifies proof of delivery
  static Future<void> adminVerifyDelivery(String assignmentId) async {
    final user = FirebaseAuth.instance.currentUser;

    final doc = await _db.collection(_collection).doc(assignmentId).get();
    if (!doc.exists) throw Exception('Assignment not found');
    final data = doc.data()!;
    final familyId = data['familyId'] as String;

    final now = DateTime.now();
    await _db.collection(_collection).doc(assignmentId).update({
      'status': DeliveryStatus.adminVerified.toFirestore(),
      'adminVerified': true,
      'adminVerifiedAt': Timestamp.fromDate(now),
      'adminVerifiedBy': user?.uid,
      'adminVerifiedByName':
          user?.displayName ?? user?.email ?? 'Unknown admin',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update family
    await _db.collection('families').doc(familyId).update({
      'fulfillmentStatus': 'admin_verified',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update linked donations to delivered
    final donationIds = data['donationIds'] != null
        ? List<String>.from(data['donationIds'] as List)
        : <String>[];

    for (final donationId in donationIds) {
      await _db.collection('donations').doc(donationId).update({
        'status': 'delivered',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await AuditService.logFamilyAction(
      action: 'Delivery admin verified',
      familyId: familyId,
      familyName: 'Family',
      details: 'Verified by ${user?.email ?? "Admin"}',
    );
  }

  /// Admin reassigns a failed delivery to another distributor
  static Future<void> reassignDelivery({
    required String assignmentId,
    required String newDistributorId,
    required String newDistributorName,
    String? adminNote,
  }) async {
    await _db.collection(_collection).doc(assignmentId).update({
      'status': DeliveryStatus.notStarted.toFirestore(),
      'assignedDistributorId': newDistributorId,
      'assignedDistributorName': newDistributorName,
      'adminNote': adminNote,
      'failureReason': null,
      'failureNotes': null,
      'failedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await NotificationService.sendToUser(
      userId: newDistributorId,
      title: 'Delivery Reassigned to You 🚚',
      body:
          'A delivery has been reassigned to you. Please check your assignments.',
      data: {'type': 'delivery_reassigned', 'assignmentId': assignmentId},
    );
  }

  // ─── Performance Stats ─────────────────────────────────────────────────────

  /// Get performance metrics for a distributor
  static Future<Map<String, dynamic>> getDistributorPerformance(
    String distributorId,
  ) async {
    // Guard: never query Firestore with an empty distributorId
    if (distributorId.isEmpty) {
      return {
        'total': 0,
        'completed': 0,
        'failed': 0,
        'pending': 0,
        'onTime': 0,
        'completionRate': 0.0,
        'onTimeRate': 0.0,
      };
    }

    final snap = await _db
        .collection(_collection)
        .where('assignedDistributorId', isEqualTo: distributorId)
        .get();

    final assignments = snap.docs
        .map(DeliveryAssignment.fromFirestore)
        .toList();

    final total = assignments.length;
    final completed = assignments
        .where(
          (a) =>
              a.status == DeliveryStatus.delivered ||
              a.status == DeliveryStatus.adminVerified,
        )
        .length;
    final failed = assignments
        .where(
          (a) =>
              a.status == DeliveryStatus.failed ||
              a.status == DeliveryStatus.reassigned,
        )
        .length;
    final pending = assignments
        .where(
          (a) =>
              a.status == DeliveryStatus.notStarted ||
              a.status == DeliveryStatus.pickedUp ||
              a.status == DeliveryStatus.inTransit,
        )
        .length;

    // On-time: delivered before or on scheduledAt
    final onTime = assignments.where((a) {
      if (a.deliveredAt == null || a.scheduledAt == null) return false;
      return !a.deliveredAt!.isAfter(a.scheduledAt!);
    }).length;

    final completionRate = total > 0 ? (completed / total * 100) : 0.0;
    final onTimeRate = completed > 0 ? (onTime / completed * 100) : 0.0;

    return {
      'total': total,
      'completed': completed,
      'failed': failed,
      'pending': pending,
      'onTime': onTime,
      'completionRate': completionRate,
      'onTimeRate': onTimeRate,
    };
  }
}
