import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/models/donation_model.dart';
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
    Map<String, num> items = const {},
    Map<String, String> itemUnits = const {},
    List<String> inKindCoveredItems = const [],
    String? distributorId,
    String? distributorName,
    String? procurementRequestId,
    DateTime? scheduledAt,
    String? adminNote,
    WriteBatch? batch,
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
      itemUnits: itemUnits,
      inKindCoveredItems: inKindCoveredItems,
      assignedDistributorId: distributorId,
      assignedDistributorName: distributorName,
      status: DeliveryStatus.notStarted,
      scheduledAt: scheduledAt,
      procurementRequestId: procurementRequestId,
      adminNote: adminNote,
      createdAt: now,
      updatedAt: now,
    );

    if (batch != null) {
      batch.set(ref, assignment.toFirestore());
    } else {
      await ref.set(assignment.toFirestore());
    }

    // Notify the assigned distributor (or broadcast to pool)
    if (distributorId != null) {
      await NotificationService.sendToUser(
        userId: distributorId,
        title: 'New Delivery Assigned 🚚',
        body:
            'You have a new delivery to $familyArea, $familyCity. Tap to view details.',
        data: {'type': 'delivery_assigned', 'assignmentId': ref.id},
      );
    } else {
      await NotificationService.notifyAllDistributors(
        title: 'New Delivery Available 📦',
        message:
            'A new pack delivery for $familyArea, $familyCity is available in the pool. Claim it now!',
        actionType: 'new_delivery_pool',
        actionId: ref.id,
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

  /// Stream historical assignments for a specific distributor (delivered, failed, etc).
  static Stream<List<DeliveryAssignment>> streamDistributorHistory(
    String distributorId,
  ) {
    if (distributorId.isEmpty) return const Stream.empty();

    return _db
        .collection(_collection)
        .where('assignedDistributorId', isEqualTo: distributorId)
        .where(
          'status',
          whereIn: ['delivered', 'failed', 'admin_verified', 'reassigned'],
        )
        .snapshots()
        .map((s) {
          final list = s.docs.map(DeliveryAssignment.fromFirestore).toList();
          list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return list;
        });
  }

  /// Smart stream: supervisor sees ALL assignments, member sees own only.
  /// Mirrors ProcurementService.getSmartHomeStatsStream()
  static Stream<List<DeliveryAssignment>> getSmartDeliveryStream(
    String distributorId,
    bool isSupervisor,
  ) {
    if (isSupervisor) {
      return streamAllAssignments(); // global
    }
    return streamAssignmentsByDistributor(distributorId); // personal
  }

  /// Smart history stream: supervisor sees ALL history, member sees own.
  /// Mirrors ProcurementService.getSmartHistoryStream()
  static Stream<List<DeliveryAssignment>> getSmartHistoryStream(
    String distributorId,
    bool isSupervisor,
  ) {
    if (isSupervisor) {
      return streamAllHistory(); // global
    }
    return streamDistributorHistory(distributorId); // personal
  }

  /// Stream ALL historical assignments across all distributors.
  static Stream<List<DeliveryAssignment>> streamAllHistory() {
    return _db
        .collection(_collection)
        .where(
          'status',
          whereIn: ['delivered', 'failed', 'admin_verified', 'reassigned'],
        )
        .snapshots()
        .map((s) {
          final list = s.docs.map(DeliveryAssignment.fromFirestore).toList();
          list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return list;
        });
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
        // Guard 1: Already claimed by another distributor
        if (current['assignedDistributorId'] != null) {
          throw Exception('already_claimed');
        }
        // Guard 2: Status must still be not_started (prevents partial-write orphans)
        if (current['status'] != 'not_started') {
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

      // Notify Admin that a delivery has been claimed
      final doc = await ref.get();
      if (doc.exists) {
        final familyArea = doc.data()?['familyArea'] ?? '';
        await NotificationService.sendAdminNotification(
          title: 'Delivery Claimed 🚚',
          message:
              '$distributorName has claimed the delivery assignment for $familyArea.',
          type: 'delivery_claimed',
          relatedId: assignmentId,
        );
      }

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
    final doc = await _db.collection(_collection).doc(assignmentId).get();
    if (!doc.exists) return;

    final assignment = DeliveryAssignment.fromFirestore(doc);

    // Use a WriteBatch so the assignment update and warehouse stock clearing are atomic.
    final batch = _db.batch();

    // 1. Advance delivery assignment status
    batch.update(_db.collection(_collection).doc(assignmentId), {
      'status': DeliveryStatus.pickedUp.toFirestore(),
      'pickedUpAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Advance procurement to in_transit — pack is now in the hands of the distributor
    if (assignment.procurementRequestId != null) {
      batch.update(
        _db.collection('procurement_requests').doc(assignment.procurementRequestId),
        {'status': 'in_transit'}, // Purchaser sees "Out for Delivery"
      );
    }

    // 3. Clear family-reserved in-kind stock from the Purchaser In-Kind Warehouse tab.
    //    When a delivery is picked up for a family (procurement OR in-kind), the physical
    //    items are leaving the warehouse — advance warehouse_stock to 'in_transit' so
    //    they stop appearing in the Family Reserved view (which only shows
    //    'received' and 'pending_pickup').
    final stockSnaps = await _db
        .collection('warehouse_stock')
        .where('familyId', isEqualTo: assignment.familyId)
        .where('status', whereIn: ['received', 'pending_pickup'])
        .get();

    for (final sDoc in stockSnaps.docs) {
      batch.update(sDoc.reference, {
        'status': 'in_transit',
        'pickedUpAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Commit atomically
    await batch.commit();

    // 4. Notify Admin that items have been collected (after commit — non-blocking)
    await NotificationService.sendAdminNotification(
      title: 'Items Picked Up from Warehouse 📦',
      message:
          'Delivery for ${assignment.familyArea} has been collected from the warehouse by the distributor.',
      type: 'delivery_pickup',
      relatedId: assignmentId,
    );
  }

  /// Move assignment to In Transit
  static Future<void> markInTransit(String assignmentId) async {
    await _db.collection(_collection).doc(assignmentId).update({
      'status': DeliveryStatus.inTransit.toFirestore(),
      'inTransitAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Sync donations to out_for_delivery
    // Fix #4: include 'verified' as safety net in case earlier stages didn't catch them
    final doc = await _db.collection(_collection).doc(assignmentId).get();
    final familyId = doc.data()?['familyId'] as String?;
    if (familyId != null) {
      await _syncDonationsToStatus(
        familyId,
        [
          DonationStatus.inProcess.toFirestore(),
          DonationStatus.stocked.toFirestore(),
          DonationStatus.verified.toFirestore(), // safety net
        ],
        DonationStatus.outForDelivery.toFirestore(),
        'Your donation is on the way to the family!',
      );

      // Notify donors of all donations now marked out_for_delivery
      final updatedSnaps = await _db
          .collection('donations')
          .where('familyId', isEqualTo: familyId)
          .where('status', isEqualTo: DonationStatus.outForDelivery.toFirestore())
          .get();
      // Collect unique donorIds to avoid duplicate notifications
      final notifiedDonors = <String>{};
      for (final dDoc in updatedSnaps.docs) {
        final donorId = dDoc.data()['donorId'] as String? ?? '';
        final isSlice = dDoc.data()['isSmartSplitSlice'] as bool? ?? false;
        // Only notify on parent donations or direct donations, not on child slices
        // (the parent will carry the notification for the whole smart donation).
        if (donorId.isNotEmpty && !isSlice && !notifiedDonors.contains(donorId)) {
          notifiedDonors.add(donorId);
          await NotificationService.sendDonorNotification(
            userId: donorId,
            title: 'Your Donation is On the Way! 🚚',
            message:
                'Great news! Your donation is now out for delivery to the family. It should arrive very soon!',
            actionType: 'donation_out_for_delivery',
            actionId: dDoc.id,
          );
        }
      }
    }
  }

  // ─── Proof of Delivery ─────────────────────────────────────────────────────

  /// Submit proof of delivery: upload photo + save GPS
  ///
  /// [capturedAt] — the actual moment the proof was captured (critical for
  /// offline sync: pass the savedAt time from the offline queue so Firestore
  /// records the TRUE delivery time, not the upload/sync time).
  static Future<void> submitProofOfDelivery({
    required String assignmentId,
    required String familyId,
    required File proofPhoto,
    double? lat,
    double? lng,
    String? reverseGeocodedAddress,
    List<String> donorIds = const [],
    // FIX 3: Use actual capture time instead of upload time for offline proofs.
    // When null (online submissions), defaults to now — identical to old behaviour.
    DateTime? capturedAt,
    // FIX 2: Reason the geofence was skipped (e.g. 'family_coords_missing').
    // Stored in Firestore so admin card can display a yellow "No Family GPS" badge.
    String? geoSkippedReason,
  }) async {
    // 1. Upload photo to Cloudinary
    final response = await CloudinaryService.uploadImage(proofPhoto);
    if (!response.isSuccess) {
      throw Exception(response.errorMessage ?? 'Failed to upload proof photo');
    }
    final photoUrl = response.url!;

    // FIX D10: Fetch assignment details BEFORE starting the batch to avoid stale cache reads
    final assignmentRef = _db.collection(_collection).doc(assignmentId);
    final assignmentDoc = await assignmentRef.get();
    final assignment = DeliveryAssignment.fromFirestore(assignmentDoc);

    // FIX 3: Use the actual capture timestamp if provided (offline sync case).
    // Online submissions pass null so this falls back to now — no behaviour change.
    final proofTime = capturedAt ?? DateTime.now();
    final batch = _db.batch();

    // 2. Update delivery assignment
    batch.update(assignmentRef, {
      'status': DeliveryStatus.delivered.toFirestore(),
      'deliveredAt': Timestamp.fromDate(proofTime),
      'proofPhotoUrl': photoUrl,
      'proofGeoLat': lat,
      'proofGeoLng': lng,
      'proofTimestamp': Timestamp.fromDate(proofTime),
      'proofAddress': reverseGeocodedAddress,
      if (geoSkippedReason != null) 'geoSkippedReason': geoSkippedReason,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3. Update family fulfillment status
    final familyRef = _db.collection('families').doc(familyId);
    batch.update(familyRef, {
      'fulfillmentStatus': 'delivered',
      'deliveredAt': Timestamp.fromDate(proofTime),
      'deliveryProof': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3b. Procurement stays in_transit — only Admin verification advances it to delivered
    // (Invisible Review: do NOT set procurement to delivered here yet)

    // 3c. Liquidate targeted in-kind warehouse stock
    if (assignment.inKindCoveredItems.isNotEmpty) {
      final stockSnaps = await _db
          .collection('warehouse_stock')
          .where('familyId', isEqualTo: familyId)
          .where(
            'status',
            whereIn: ['pending_pickup', 'in_transit', 'received'],
          )
          .get();
      for (final sDoc in stockSnaps.docs) {
        batch.update(sDoc.reference, {
          'status': 'delivered',
          'deliveredAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // Commit all state updates atomically
    await batch.commit();

    // 4. Notify admin for verification
    await NotificationService.sendToRole(
      role: 'admin',
      title: 'Delivery Proof Submitted 📦',
      body: 'A delivery proof has been submitted and needs your verification.',
      data: {'type': 'delivery_proof_submitted', 'assignmentId': assignmentId},
    );

    await AuditService.logFamilyAction(
      action: 'Delivery proof submitted',
      familyId: familyId,
      familyName: 'Family',
      details: 'Proof photo uploaded. GPS: ${lat ?? "N/A"}, ${lng ?? "N/A"}',
    );
  }

  static Future<void> _syncDonationsToStatus(
    String familyId,
    List<String> allowedPriorStatuses,
    String newStatus,
    String notificationNote,
  ) async {
    final snaps = await _db
        .collection('donations')
        .where('familyId', isEqualTo: familyId)
        .where('status', whereIn: allowedPriorStatuses)
        .get();

    if (snaps.docs.isEmpty) {
      // Still try to advance parent smart donations even if no direct donations found
      await _syncParentSmartDonations(familyId, newStatus, notificationNote);
      return;
    }

    final batch = _db.batch();
    for (final doc in snaps.docs) {
      batch.update(doc.reference, {
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': newStatus,
            'timestamp': Timestamp.now(),
            'note': notificationNote,
          }
        ]),
      });
    }
    await batch.commit();

    // Also advance any parent Smart Give donations whose slices belong to this family
    await _syncParentSmartDonations(familyId, newStatus, notificationNote);
  }

  /// Updates parent Smart Give donation when a family's slices advance.
  /// Only ever increases status — never regresses.
  static Future<void> _syncParentSmartDonations(
    String familyId,
    String newStatus,
    String note,
  ) async {
    const statusOrder = [
      'draft', 'pending', 'under_verification', 'verified',
      'stocked', 'in_process', 'out_for_delivery', 'delivered', 'closed',
    ];
    final newIdx = statusOrder.indexOf(newStatus);
    if (newIdx < 0) return;

    // Find smart-split slices for this family
    final sliceSnaps = await _db
        .collection('donations')
        .where('familyId', isEqualTo: familyId)
        .where('isSmartSplitSlice', isEqualTo: true)
        .get();
    if (sliceSnaps.docs.isEmpty) return;

    final parentIds = sliceSnaps.docs
        .map((d) => d.data()['parentDonationId'] as String?)
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    if (parentIds.isEmpty) return;

    for (final parentId in parentIds) {
      final parentRef = _db.collection('donations').doc(parentId!);
      final parentDoc = await parentRef.get();
      if (!parentDoc.exists) continue;

      final currentStatus = parentDoc.data()?['status'] as String? ?? 'draft';
      final currentIdx = statusOrder.indexOf(currentStatus);
      // Never regress
      if (newIdx <= currentIdx) continue;

      await parentRef.update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': newStatus,
            'timestamp': Timestamp.now(),
            'note': note,
          }
        ]),
      });
    }
  }

  // ─── Offline Proof Queue ───────────────────────────────────────────────────

  /// Save proof locally when offline.
  ///
  /// FIX 3: We now persist [capturedAt] — the exact moment the distributor
  /// captured the proof at the family's door. This timestamp is passed to
  /// [submitProofOfDelivery] on sync so Firestore records the TRUE delivery
  /// time rather than the (potentially hours-later) upload time.
  static Future<void> saveProofOffline({
    required String assignmentId,
    required String familyId,
    required String localPhotoPath,
    double? lat,
    double? lng,
    String? reverseGeocodedAddress,
    List<String> donorIds = const [],
    String? geoSkippedReason,
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
      // FIX 3: Store actual capture time — used as proofTimestamp on sync.
      'capturedAt': DateTime.now().toIso8601String(),
      'savedAt': DateTime.now().toIso8601String(),
      if (geoSkippedReason != null) 'geoSkippedReason': geoSkippedReason,
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

        // FIX 3: Parse the actual capture time saved offline.
        // If capturedAt is missing from an older queue entry, fall back to
        // savedAt, then to null (which defaults to now inside submitProofOfDelivery).
        DateTime? capturedAt;
        final capturedAtRaw =
            data['capturedAt'] as String? ?? data['savedAt'] as String?;
        if (capturedAtRaw != null) {
          capturedAt = DateTime.tryParse(capturedAtRaw);
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
          capturedAt: capturedAt, // FIX 3: Pass actual capture time
          geoSkippedReason: data['geoSkippedReason'] as String?,
        );
        synced++;

        // Gap 1 Fix: Delete the physical image file from storage if sync succeeds
        try {
          if (file.existsSync()) {
            file.deleteSync();
          }
        } catch (e) {
          // Keep silently failing if file deletion errors, to prevent sync halting
        }
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
    final batch = _db.batch();

    // 1. Update assignment status
    final assignmentRef = _db.collection(_collection).doc(assignmentId);
    batch.update(assignmentRef, {
      'status': DeliveryStatus.failed.toFirestore(),
      'failedAt': FieldValue.serverTimestamp(),
      'failureReason': reason.toFirestore(),
      'failureNotes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Cascade failure back to family fulfillment status
    final familyRef = _db.collection('families').doc(familyId);
    batch.update(familyRef, {
      'fulfillmentStatus': 'issue_reported',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3. Procurement stays at in_transit during failure — Purchaser is shielded from
    //    delivery drama. It will only advance to delivered on Admin verification.

    // Commit atomic failure
    await batch.commit();

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
      details:
          'Reason: ${reason.displayName}. Notes: $notes.',
    );
  }

  // ─── Failed Delivery Recovery ──────────────────────────────────────────────

  /// Distributor re-attempts a failed/rejected delivery
  static Future<void> reattemptDelivery(String assignmentId) async {
    final doc = await _db.collection(_collection).doc(assignmentId).get();
    if (!doc.exists) throw Exception('Assignment not found');
    final data = doc.data()!;
    final familyId = data['familyId'] as String;

    final batch = _db.batch();

    // 1. Reset assignment status
    batch.update(_db.collection(_collection).doc(assignmentId), {
      'status': DeliveryStatus.inTransit.toFirestore(),
      'failedAt': null,
      'failureReason': null,
      'failureNotes': null,
      'proofPhotoUrl': null, // Clear any rejected proof photo
      'proofGeoLat': null,
      'proofGeoLng': null,
      'proofAddress': null,
      'proofTimestamp': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Reset family fulfillment status mapping
    batch.update(_db.collection('families').doc(familyId), {
      'fulfillmentStatus': 'ready_for_delivery',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    // 3. Procurement stays at in_transit during reattempt — no regression for Purchaser

    // 4. Advance linked donations back to out_for_delivery from verified
    final donationIds = data['donationIds'] != null
        ? List<String>.from(data['donationIds'] as List)
        : <String>[];

    for (final donationId in donationIds) {
      batch.update(_db.collection('donations').doc(donationId), {
        'status': 'out_for_delivery',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Update smart parent donations
    await batch.commit();

    // Also sync parent smart donations properly (it bumps them if needed)
    await _syncDonationsToStatus(
      familyId,
      [DonationStatus.verified.toFirestore()],
      DonationStatus.outForDelivery.toFirestore(),
      'Delivery is being re-attempted.',
    );

    await AuditService.logFamilyAction(
      action: 'Delivery re-attempted',
      familyId: familyId,
      familyName: 'Assignment $assignmentId',
      details: 'Distributor initiated a re-attempt. Status reverted to in_transit.',
    );
  }

  // ─── Admin Actions ─────────────────────────────────────────────────────────

  /// Admin verifies proof of delivery — ATOMIC via WriteBatch
  static Future<void> adminVerifyDelivery(String assignmentId) async {
    final user = FirebaseAuth.instance.currentUser;

    final doc = await _db.collection(_collection).doc(assignmentId).get();
    if (!doc.exists) throw Exception('Assignment not found');
    final data = doc.data()!;
    final familyId = data['familyId'] as String;

    final now = DateTime.now();
    final batch = _db.batch();

    // 1. Update assignment status
    batch.update(_db.collection(_collection).doc(assignmentId), {
      'status': DeliveryStatus.adminVerified.toFirestore(),
      'adminVerified': true,
      'adminVerifiedAt': Timestamp.fromDate(now),
      'adminVerifiedBy': user?.uid,
      'adminVerifiedByName':
          user?.displayName ?? user?.email ?? 'Unknown admin',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Update family fulfillment status
    batch.update(_db.collection('families').doc(familyId), {
      'fulfillmentStatus': 'admin_verified',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3. Advance procurement to delivered — ONLY here, after Admin verification
    final procId = data['procurementRequestId'] as String?;
    if (procId != null) {
      batch.update(_db.collection('procurement_requests').doc(procId), {
        'status': 'delivered',
      });
    }

    // Commit atomically — assignment, family, and procurement succeed or none do
    await batch.commit();

    // 3. Update linked donations to delivered (and parent smart donations)
    await _syncDonationsToStatus(
      familyId,
      [DonationStatus.outForDelivery.toFirestore()],
      DonationStatus.delivered.toFirestore(),
      'Donation officially verified and delivered.',
    );

    await AuditService.logFamilyAction(
      action: 'Delivery admin verified',
      familyId: familyId,
      familyName: 'Family',
      details: 'Verified by ${user?.email ?? "Admin"}. Donations marked delivered.',
    );

    // Notify Distributor
    final distributorId = data['assignedDistributorId'] as String?;
    if (distributorId != null) {
      await NotificationService.sendDistributorNotification(
        userId: distributorId,
        title: 'Delivery Officially Verified ✅',
        message: 'Admin has confirmed your delivery. Great work! This delivery is now complete.',
        actionType: 'delivery_admin_verified',
        actionId: assignmentId,
      );
    }

    // Notify Donors
    final donationIds = data['donationIds'] != null
        ? List<String>.from(data['donationIds'] as List)
        : <String>[];
        
    for (final donationId in donationIds) {
      final donDoc = await _db.collection('donations').doc(donationId).get();
      final donorId = donDoc.data()?['donorId'] as String?;
      if (donorId != null) {
        await NotificationService.sendDonorNotification(
          userId: donorId,
          title: 'Delivery Officially Verified ✅',
          message: 'An Admin has confirmed your donation reached the family safely!',
          actionType: 'delivery_admin_verified',
          actionId: assignmentId,
        );
      }
    }

    // Also notify donors of Smart Give parent donations linked to this family.
    // Smart parents are NOT listed in donationIds (which holds direct slice IDs).
    final parentSliceSnaps = await _db
        .collection('donations')
        .where('familyId', isEqualTo: familyId)
        .where('isSmartSplitSlice', isEqualTo: true)
        .get();
    final parentIds = parentSliceSnaps.docs
        .map((d) => d.data()['parentDonationId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final alreadyNotifiedDonors = <String>{};
    for (final parentId in parentIds) {
      final parentDoc = await _db.collection('donations').doc(parentId).get();
      if (!parentDoc.exists) continue;
      final donorId = parentDoc.data()?['donorId'] as String? ?? '';
      if (donorId.isNotEmpty && !alreadyNotifiedDonors.contains(donorId)) {
        alreadyNotifiedDonors.add(donorId);
        await NotificationService.sendDonorNotification(
          userId: donorId,
          title: 'Smart Donation Delivered! ❤️',
          message:
              'Your Smart Give donation has been officially verified and delivered to a family in need. Thank you for your generosity!',
          actionType: 'delivery_admin_verified',
          actionId: parentId,
        );
      }
    }
  }


  /// Admin rejects proof of delivery — ATOMIC via WriteBatch
  static Future<void> adminRejectDelivery(String assignmentId) async {
    final user = FirebaseAuth.instance.currentUser;
    final doc = await _db.collection(_collection).doc(assignmentId).get();
    if (!doc.exists) return;
    
    final data = doc.data()!;
    final familyId = data['familyId'] as String;

    final batch = _db.batch();

    // 1. Update assignment status to failed.
    // FIX 4: Also clear ALL proof fields so the stale rejected photo/GPS
    // cannot linger on the record and confuse future admin reviews or
    // accidentally get re-verified after the distributor reattempts.
    batch.update(_db.collection(_collection).doc(assignmentId), {
      'status': DeliveryStatus.failed.toFirestore(),
      'failedAt': FieldValue.serverTimestamp(),
      'failureReason': DeliveryFailureReason.other.toFirestore(),
      'failureNotes': 'Proof rejected by Administrator (${user?.email ?? "Admin"}).',
      // FIX 4: Wipe stale proof data on rejection
      'proofPhotoUrl': null,
      'proofGeoLat': null,
      'proofGeoLng': null,
      'proofTimestamp': null,
      'proofAddress': null,
      'geoSkippedReason': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Cascade failure back to family
    batch.update(_db.collection('families').doc(familyId), {
      'fulfillmentStatus': 'issue_reported',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3. Cascade failure back to procurement
    final procId = data['procurementRequestId'] as String?;
    if (procId != null) {
      batch.update(_db.collection('procurement_requests').doc(procId), {
        'status': 'issue_reported'
      });
    }

    await batch.commit();

    await AuditService.logFamilyAction(
      action: 'Delivery proof rejected',
      familyId: familyId,
      familyName: 'Family',
      details: 'Proof rejected by ${user?.email ?? "Admin"}. All proof fields cleared.',
    );

    // Notify Distributor
    final distributorId = data['assignedDistributorId'] as String?;
    if (distributorId != null) {
      await NotificationService.sendDistributorNotification(
        userId: distributorId,
        title: 'Delivery Proof Rejected ❌',
        message: 'Admin rejected your submitted proof of delivery. Please reattempt and submit a new photo.',
        actionType: 'delivery_admin_rejected',
        actionId: assignmentId,
      );
    }
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

  // ─── One-Time Data Migration ────────────────────────────────────────────────

  /// Fixes procurement_requests that were incorrectly set to 'issue_reported'
  /// by old code. Resets them to 'in_transit' if the delivery is still active
  /// (not yet admin_verified or delivered). Safe to call multiple times.
  static Future<void> migrateIssueReportedProcurements() async {
    try {
      // Find all procurement requests stuck at issue_reported
      final snap = await _db
          .collection('procurement_requests')
          .where('status', isEqualTo: 'issue_reported')
          .get();

      if (snap.docs.isEmpty) return; // Nothing to fix

      final batch = _db.batch();
      int fixedCount = 0;

      for (final procDoc in snap.docs) {
        final procId = procDoc.id;

        // Find the linked delivery assignment for this procurement
        final assignmentSnap = await _db
            .collection(_collection)
            .where('procurementRequestId', isEqualTo: procId)
            .limit(1)
            .get();

        if (assignmentSnap.docs.isEmpty) continue;

        final assignmentData = assignmentSnap.docs.first.data();
        final assignmentStatus = assignmentData['status'] as String? ?? '';

        // Only fix if delivery is NOT yet finished (admin_verified or delivered)
        // If the delivery is truly done, leave it as-is
        const finishedStatuses = ['admin_verified', 'delivered'];
        if (finishedStatuses.contains(assignmentStatus)) continue;

        // Reset to in_transit — pack is physically still out for delivery
        batch.update(
          _db.collection('procurement_requests').doc(procId),
          {'status': 'in_transit'},
        );
        fixedCount++;
      }

      if (fixedCount > 0) {
        await batch.commit();
        debugPrint(
          '[DeliveryService] Migration: Fixed $fixedCount procurement(s) from issue_reported → in_transit',
        );
      }
    } catch (e) {
      // Non-critical — log and swallow so it never crashes the app
      debugPrint('[DeliveryService] Migration error (non-fatal): $e');
    }
  }

  // REPAIR TOOL — one-time data fix
  // ───────────────────────────────────────────────────────────────────────

  /// One-time repair: clears warehouse_stock docs that are still stuck at
  /// 'received' or 'pending_pickup' for families whose delivery has already
  /// been picked up (status: picked_up, in_transit, delivered, failed, admin_verified).
  /// Safe to call multiple times — guards against already-fixed docs.
  static Future<void> repairStuckWarehouseStock() async {
    try {
      // Find all delivery assignments that have been picked up or beyond
      final assignmentsSnap = await _db
          .collection(_collection)
          .where('status', whereIn: [
            'picked_up',
            'in_transit',
            'delivered',
            'failed',
            'admin_verified',
          ])
          .get();

      if (assignmentsSnap.docs.isEmpty) {
        debugPrint('[DeliveryService] Repair: No picked-up assignments found.');
        return;
      }

      int fixedCount = 0;
      final batch = _db.batch();

      for (final assignmentDoc in assignmentsSnap.docs) {
        final data = assignmentDoc.data();
        final familyId = data['familyId'] as String?;

        // Only process deliveries with a valid family
        if (familyId == null || familyId.isEmpty) continue;

        // Find warehouse_stock still stuck at received/pending_pickup for this family
        final stockSnaps = await _db
            .collection('warehouse_stock')
            .where('familyId', isEqualTo: familyId)
            .where('status', whereIn: ['received', 'pending_pickup'])
            .get();

        for (final sDoc in stockSnaps.docs) {
          batch.update(sDoc.reference, {
            'status': 'in_transit',
            'pickedUpAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          fixedCount++;
        }
      }

      if (fixedCount > 0) {
        await batch.commit();
        debugPrint(
          '✅ [DeliveryService] Repair: Fixed $fixedCount stuck warehouse_stock doc(s) → in_transit.',
        );
      } else {
        debugPrint(
          'ℹ️ [DeliveryService] Repair: No stuck warehouse_stock docs found.',
        );
      }
    } catch (e) {
      debugPrint('[DeliveryService] Repair error (non-fatal): $e');
    }
  }
}
