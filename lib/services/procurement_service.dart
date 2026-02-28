import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/models/assistance_pack_model.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:ration_aid/services/delivery_service.dart';

class ProcurementService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'procurement_requests';

  /// Auto-generate procurement requests for eligible families
  /// Call this when funding Status changes to 'fully_funded'
  static Future<void> checkAndGenerateRequest(String familyId) async {
    try {
      final familyDoc = await _firestore
          .collection('families')
          .doc(familyId)
          .get();
      if (!familyDoc.exists) return;

      final family = Family.fromFirestore(familyDoc);

      // Criteria:
      // 1. Fully Funded (or raised + pending >= target)
      // 2. Pack Assigned
      // 3. No existing active request

      final isFunded =
          (family.raisedAmount + family.pendingAmount) >= family.targetAmount;
      if (!isFunded || family.assignedPackId == null) return;

      // Check existing — include 'stocked' to prevent double-ordering
      final existingQuery = await _firestore
          .collection(_collection)
          .where('familyId', isEqualTo: familyId)
          .where(
            'status',
            whereIn: ['pending', 'purchased', 'verified', 'stocked'],
          )
          .get();

      if (existingQuery.docs.isNotEmpty) return; // Already exists

      // Retrieve Pack Details
      final packDoc = await _firestore
          .collection('assistance_packs')
          .doc(family.assignedPackId)
          .get();
      if (!packDoc.exists) return;
      final pack = AssistancePack.fromFirestore(packDoc);

      // Create Request
      final request = ProcurementRequest(
        id: '', // Auto-id
        familyId: family.id,
        familyAddress: family.area, // Only show Area to purchaser
        packId: pack.id,
        packName: pack.name,
        items: pack.items
            .map(
              (item) => ProcurementItem(
                name: item.name,
                quantity: item.quantity,
                estimatedCost: item.estimatedCost,
              ),
            )
            .toList(),
        // Budget = sum of pack's estimated item costs (not family donation target)
        budgetLimit: pack.items.fold(
          0.0,
          (acc, item) => acc + item.estimatedCost,
        ),
        createdAt: DateTime.now(),
        status: ProcurementStatus.pending,
      );

      await _firestore.collection(_collection).add(request.toFirestore());

      // Update family status
      await _firestore.collection('families').doc(familyId).update({
        'fulfillmentStatus': 'ready_for_purchase',
      });

      // Notify all purchasers
      await NotificationService.notifyAllPurchasers(
        title: 'New Request Available 📦',
        message:
            'A new pack "${pack.name}" is ready for purchase in ${family.area}.',
        actionType: 'new_request',
        actionId:
            family.id, // Using family ID as action ID to maybe filter/highlight
      );
    } catch (e) {
      debugPrint('Error generating procurement request: $e');
      rethrow;
    }
  }

  /// Get pending requests for Purchaser Dashboard
  static Stream<List<ProcurementRequest>> getPendingRequestsStream() {
    return _firestore
        .collection(_collection)
        .where('status', whereIn: ['pending', 'purchased', 'rejected'])
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ProcurementRequest.fromFirestore(doc))
              .toList(),
        );
  }

  /// Get active inventory (Stocked items waiting for delivery)
  static Stream<List<ProcurementRequest>> getInventoryStream() {
    return _firestore
        .collection(_collection)
        .where(
          'status',
          whereIn: ['verified', 'stocked'],
        ) // Includes stocked (In Progress)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ProcurementRequest.fromFirestore(doc))
              .toList(),
        );
  }

  /// Get ALL requests for filtering
  static Stream<List<ProcurementRequest>> getAllRequestsStream() {
    return _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ProcurementRequest.fromFirestore(doc))
              .toList(),
        );
  }

  /// Smart stream for Home Stats (Global vs Personal based on isSupervisor)
  static Stream<List<ProcurementRequest>> getSmartHomeStatsStream(
    String purchaserId,
    bool isSupervisor,
  ) {
    if (isSupervisor) {
      return getAllRequestsStream(); // Supervisors see global stats
    } else {
      // Regular purchasers only see items they claimed or submitted
      return streamMyRequests(purchaserId);
    }
  }

  // ─── Self-Claim Pool ─────────────────────────────────────────────────────

  /// Stream unclaimed pending orders — the shared pool every purchaser sees.
  static Stream<List<ProcurementRequest>> streamAvailableRequests() {
    return _firestore
        .collection(_collection)
        .where('status', isEqualTo: 'pending')
        .where('claimedById', isNull: true)
        .snapshots()
        .map(
          (s) =>
              s.docs.map(ProcurementRequest.fromFirestore).toList()
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        );
  }

  /// Stream orders claimed by or submitted by a specific purchaser.
  /// Covers: claimed-but-not-yet-submitted AND purchased/rejected (personal pipeline).
  static Stream<List<ProcurementRequest>> streamMyRequests(String purchaserId) {
    // Two Firestore queries merged client-side:
    //   1. Claimed (pending + claimedById == uid)
    //   2. Already submitted (purchaserId == uid, any post-pending status)
    final claimedStream = _firestore
        .collection(_collection)
        .where('claimedById', isEqualTo: purchaserId)
        .snapshots()
        .map((s) => s.docs.map(ProcurementRequest.fromFirestore).toList());

    final submittedStream = _firestore
        .collection(_collection)
        .where('purchaserId', isEqualTo: purchaserId)
        .snapshots()
        .map((s) => s.docs.map(ProcurementRequest.fromFirestore).toList());

    // Merge and deduplicate by id
    return claimedStream.asyncExpand((claimed) {
      return submittedStream.map((submitted) {
        final seen = <String>{};
        final merged = <ProcurementRequest>[];
        for (final r in [...claimed, ...submitted]) {
          if (seen.add(r.id)) merged.add(r);
        }
        merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return merged;
      });
    });
  }

  /// Smart UID-filtered history stream (Global if supervisor, personal if not)
  static Stream<List<ProcurementRequest>> getSmartHistoryStream(
    String purchaserId,
    bool isSupervisor,
  ) {
    if (isSupervisor) {
      return _firestore
          .collection(_collection)
          .where('status', whereIn: ['verified', 'rejected', 'delivered'])
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(ProcurementRequest.fromFirestore).toList());
    } else {
      return _firestore
          .collection(_collection)
          .where('purchaserId', isEqualTo: purchaserId)
          .where('status', whereIn: ['verified', 'rejected', 'delivered'])
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(ProcurementRequest.fromFirestore).toList());
    }
  }

  /// How many active claims this purchaser currently has (max allowed: 2).
  static Future<int> getMyActiveClaimsCount(String purchaserId) async {
    final snap = await _firestore
        .collection(_collection)
        .where('claimedById', isEqualTo: purchaserId)
        .where('status', isEqualTo: 'pending')
        .get();
    return snap.docs.length;
  }

  /// Atomically claim an unclaimed order — prevents two purchasers claiming the same order.
  /// Returns true on success, false if already claimed or limit reached.
  static Future<bool> claimRequest({
    required String requestId,
    required String purchaserId,
    required String purchaserName,
  }) async {
    // Guard: max 2 concurrent active claims
    final active = await getMyActiveClaimsCount(purchaserId);
    if (active >= 2) return false;

    final ref = _firestore.collection(_collection).doc(requestId);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw Exception('not_found');
        final data = snap.data()!;
        if (data['claimedById'] != null) throw Exception('already_claimed');
        if (data['status'] != 'pending') throw Exception('not_pending');

        tx.update(ref, {
          'claimedById': purchaserId,
          'claimedByName': purchaserName,
          'claimedAt': FieldValue.serverTimestamp(),
        });
      });

      await AuditService.logAction(
        action: 'claim_purchase_request',
        entityType: 'procurement',
        entityId: requestId,
        details: '$purchaserName claimed the purchase order',
      );
      return true;
    } catch (e) {
      if (e.toString().contains('already_claimed')) return false;
      if (e.toString().contains('not_pending')) return false;
      rethrow;
    }
  }

  /// Release a claimed order back to the pool (before submission).
  static Future<void> releaseRequest({
    required String requestId,
    required String releasedByName,
  }) async {
    await _firestore.collection(_collection).doc(requestId).update({
      'claimedById': null,
      'claimedByName': null,
      'claimedAt': null,
    });
    await AuditService.logAction(
      action: 'release_purchase_request',
      entityType: 'procurement',
      entityId: requestId,
      details: '$releasedByName released the purchase order back to pool',
    );
  }

  /// Supervisor forces a release from an AWOL purchaser back to the pool.
  static Future<void> forceReleaseRequest({
    required String requestId,
    required String adminName,
    required String previousPurchaserName,
  }) async {
    await _firestore.collection(_collection).doc(requestId).update({
      'claimedById': null,
      'claimedByName': null,
      'claimedAt': null,
    });
    await AuditService.logAction(
      action: 'force_release_purchase_request',
      entityType: 'procurement',
      entityId: requestId,
      details:
          '$adminName forcibly unassigned the order from $previousPurchaserName',
    );
  }

  /// Stream all active claims across the entire system (for supervisors).
  static Stream<List<ProcurementRequest>> streamAllActiveClaims() {
    return _firestore
        .collection(_collection)
        .where('status', isEqualTo: 'pending')
        .where('claimedById', isNull: false)
        .snapshots()
        .map(
          (s) => s.docs.map(ProcurementRequest.fromFirestore).toList()
            ..sort(
              (a, b) => (b.claimedAt ?? b.createdAt).compareTo(
                a.claimedAt ?? a.createdAt,
              ),
            ),
        );
  }

  /// Purchaser submits purchase (receipt upload)
  static Future<void> submitPurchase({
    required String requestId,
    required String purchaserId,
    required String purchaserName,
    required String receiptUrl,
    required double totalSpent,
    required List<ProcurementItem> updatedItems,
    required String packName,
  }) async {
    try {
      await _firestore.collection(_collection).doc(requestId).update({
        'status': 'purchased',
        'purchaserId': purchaserId,
        'purchaserName': purchaserName,
        'receiptUrl': receiptUrl,
        'totalSpent': totalSpent,
        'items': updatedItems.map((e) => e.toMap()).toList(),
        'purchasedAt': FieldValue.serverTimestamp(),
      });

      // Notify Admins
      await NotificationService.notifyPurchaseSubmitted(
        requestId: requestId,
        purchaserName: purchaserName,
        packName: packName,
      );

      await AuditService.logAction(
        action: 'submit_purchase',
        entityType: 'procurement',
        entityId: requestId,
        details: 'Purchaser submitted purchase for review',
      );
    } catch (e) {
      debugPrint('Error submitting purchase: $e');
      rethrow;
    }
  }

  /// Admin verifies purchase (Stock In) → auto-creates DeliveryAssignment
  static Future<void> adminVerifyPurchase(String requestId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(requestId).get();
      final request = ProcurementRequest.fromFirestore(doc);

      // 1. Mark procurement request as verified/stocked
      final batch = _firestore.batch();

      batch.update(_firestore.collection(_collection).doc(requestId), {
        'status': 'verified',
        'verifiedAt': FieldValue.serverTimestamp(),
      });

      // 2. Fetch family to get GPS location
      final familyDoc = await _firestore
          .collection('families')
          .doc(request.familyId)
          .get();
      final family = Family.fromFirestore(familyDoc);

      // Prefer admin-verified location; fall back to unverified capture
      final geoPoint = family.verifiedLocation ?? family.unverifiedLocation;
      final lat = geoPoint?.latitude;
      final lng = geoPoint?.longitude;
      final locationVerified = family.verifiedLocation != null;

      // 3. Build items map from procurement items
      // ProcurementItem.quantity is a String like "10kg" — extract leading int
      final itemsMap = <String, int>{};
      for (final item in request.items) {
        final qtyStr = RegExp(r'\d+').stringMatch(item.quantity);
        itemsMap[item.name] = qtyStr != null ? int.parse(qtyStr) : 1;
      }

      // 4. Auto-create DeliveryAssignment (links purchaser → distributor pipeline)
      await DeliveryService.createAssignment(
        familyId: request.familyId,
        familyArea: family.area,
        familyCity: family.city,
        familyAddress: family.address ?? '',
        familyPhone: family.phone,
        familySize: family.familySize,
        familyGeoLat: lat,
        familyGeoLng: lng,
        familyLocationVerified: locationVerified,
        assignedPackId: request.packId,
        assignedPackName: request.packName,
        items: itemsMap,
        procurementRequestId: requestId,
        batch: batch,
      );

      // 5. Update family status to stocked (visible in delivery module)
      batch.update(_firestore.collection('families').doc(request.familyId), {
        'fulfillmentStatus': 'stocked',
        'spentAmount': request.totalSpent,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Commit the batch to ensure total atomicity
      await batch.commit();

      // 6. Notify purchaser
      if (request.purchaserId != null) {
        await NotificationService.sendPurchaserNotification(
          userId: request.purchaserId!,
          title: 'Purchase Approved ✓',
          message:
              'Your purchase for "${request.packName}" is verified. Items are now queued for delivery.',
          actionType: 'procurement_verified',
          actionId: requestId,
        );
      }

      await AuditService.logAction(
        action: 'verify_purchase',
        entityType: 'procurement',
        entityId: requestId,
        details:
            'Admin verified purchase. Delivery assignment auto-created for ${family.area}, ${family.city}.',
      );
    } catch (e) {
      debugPrint('Error verifying purchase: $e');
      rethrow;
    }
  }

  /// Admin rejects purchase
  static Future<void> adminRejectPurchase(
    String requestId,
    String reason,
  ) async {
    try {
      final doc = await _firestore.collection(_collection).doc(requestId).get();
      final request = ProcurementRequest.fromFirestore(doc);

      await _firestore.collection(_collection).doc(requestId).update({
        'status': 'rejected',
        'adminRemarks': reason,
      });

      // Send notification to purchaser
      if (request.purchaserId != null) {
        await NotificationService.sendPurchaserNotification(
          userId: request.purchaserId!,
          title: 'Purchase Declined ✗',
          message:
              'Your purchase for "${request.packName}" was rejected. Reason: $reason',
          actionType: 'procurement_rejected',
          actionId: requestId,
        );
      }

      await AuditService.logAction(
        action: 'reject_purchase',
        entityType: 'procurement',
        entityId: requestId,
        details: 'Admin rejected purchase: $reason',
      );
    } catch (e) {
      debugPrint('Error rejecting purchase: $e');
      rethrow;
    }
  }

  /// Report an issue with inventory (Purchaser)
  static Future<void> reportIssue({
    required String requestId,
    required String issueType,
    required String reason,
    required String reportedBy,
    required String packName,
  }) async {
    try {
      await _firestore.collection(_collection).doc(requestId).update({
        'status': 'issue_reported',
        'issueType': issueType,
        'issueReason': reason,
        'issueReportedAt': FieldValue.serverTimestamp(),
        'issueReportedBy': reportedBy,
      });

      // Notify Admins
      await NotificationService.notifyIssueReported(
        requestId: requestId,
        packName: packName,
        issueType: issueType,
        reportedBy: reportedBy,
      );

      await AuditService.logAction(
        action: 'report_issue',
        entityType: 'procurement',
        entityId: requestId,
        details: 'Issue reported: $issueType - $reason',
      );
    } catch (e) {
      debugPrint('Error reporting issue: $e');
      rethrow;
    }
  }
}
