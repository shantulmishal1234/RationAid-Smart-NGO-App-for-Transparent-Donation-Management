import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/models/assistance_pack_model.dart';
import 'package:ration_aid/models/donation_model.dart';
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
          .get(const GetOptions(source: Source.server));
      if (!familyDoc.exists) return;

      final family = Family.fromFirestore(familyDoc);

      // Criteria:
      // 1. Fully Funded via combined progress (cash + in-kind value >= target)
      // 2. Based on Assistance Category (Food or Medicine)
      // 3. No existing active request
      //
      // Guard: targetAmount must be > 0 to prevent false positives on fresh
      // families with no pack assigned (0 >= 0 would otherwise trigger this).
      if (family.targetAmount <= 0) return; // No pack assigned yet — skip
      final isFunded =
          family.combinedProgress >= family.targetAmount ||
          family.raisedAmount >= family.targetAmount;
      if (!isFunded) return;

      final isMedicine = family.assistanceNeeds.contains('Medicine');
      final isFood = family.assistanceNeeds.contains('Food');

      if (!isMedicine && !isFood) return; // Unknown type

      // If Food, it must have an assigned pack
      if (isFood &&
          (family.assignedPackId == null || family.assignedPackId!.isEmpty)) {
        return;
      }

      // Check existing — include 'stocked' to prevent double-ordering
      final existingQuery = await _firestore
          .collection(_collection)
          .where('familyId', isEqualTo: familyId)
          .where(
            'status',
            whereIn: ['pending', 'purchased', 'verified', 'stocked'],
          )
          .get(const GetOptions(source: Source.server));

      if (existingQuery.docs.isNotEmpty) return; // Already exists

      // \u2500\u2500 Phase IK: Query warehouse_stock to subtract already-donated items \u2500\u2500\u2500\u2500\u2500\u2500
      // Get all 'received' in-kind batches reserved for this family.
      final Map<String, num> alreadyStocked = {};
      if (isFood) {
        final stockSnaps = await _firestore
            .collection('warehouse_stock')
            .where('familyId', isEqualTo: familyId)
            .where(
              'status',
              whereIn: ['pending_pickup', 'in_transit', 'received'],
            )
            .get(const GetOptions(source: Source.server));
        for (final doc in stockSnaps.docs) {
          final data = doc.data();
          final batchItems = Map<String, dynamic>.from(
            data['items'] as Map? ?? {},
          );
          batchItems.forEach(
            (k, v) => alreadyStocked[k] =
                (alreadyStocked[k] ?? 0) + (num.tryParse(v.toString()) ?? 0),
          );
        }
      }
      // \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

      ProcurementRequest request;

      if (isMedicine) {
        request = ProcurementRequest(
          id: '',
          familyId: family.id,
          familyAddress: family.area,
          packId: '',
          packName: 'Medical Prescription Support',
          category: 'Medicine',
          items: [
            ProcurementItem(
              name: 'Assessed Medical Supplies',
              quantity: '1 Month Supply',
              estimatedCost: family.customMedicineBudget,
            ),
          ],
          budgetLimit: family.customMedicineBudget,
          createdAt: DateTime.now(),
          status: ProcurementStatus.pending,
        );
      } else {
        // Retrieve Pack Details for Food
        final packDoc = await _firestore
            .collection('assistance_packs')
            .doc(family.assignedPackId)
            .get();
        if (!packDoc.exists) return;
        final pack = AssistancePack.fromFirestore(packDoc);

        // Build a SMART item list — subtract what's already in warehouse
        final List<ProcurementItem> smartItems = [];
        final List<String> coveredItems =
            []; // Fully covered by in-kind donations
        double smartBudget = 0.0;

        for (final item in pack.items) {
          // Use exact numeric quantity from the item model
          final rawQty = item.quantityNum;
          final stocked = alreadyStocked[item.name] ?? 0;
          final needToBuy = rawQty - stocked;

          if (needToBuy <= 0) {
            // Fully covered by in-kind donation — skip but record for banner
            coveredItems.add(item.name);
            debugPrint(
              '[Procurement] Skipping ${item.name} — already in warehouse ($stocked units)',
            );
            continue;
          }

          // Partially or fully needed — determine if partially in-kind covered
          final isPartiallyInKind = stocked > 0;
          final ratio = needToBuy / rawQty;
          final adjustedCost = item.estimatedCost * ratio;
          smartItems.add(
            ProcurementItem(
              name: item.name,
              quantity: needToBuy.toStringAsFixed(0),
              unit: item.unit, // Pass unit from pack item
              estimatedCost: adjustedCost,
              isInKindCovered: isPartiallyInKind,
            ),
          );
          smartBudget += adjustedCost;
        }

        // All items fully covered by in-kind donations — skip procurement entirely
        if (smartItems.isEmpty) {
          debugPrint(
            '[Procurement] All items for family $familyId are in warehouse. Skipping procurement.',
          );

          final batch = _firestore.batch();

          final geoPoint = family.verifiedLocation ?? family.unverifiedLocation;
          final lat = geoPoint?.latitude;
          final lng = geoPoint?.longitude;
          final locationVerified = family.verifiedLocation != null;

          // Build item map for assignment
          final itemsMap = <String, num>{};
          final itemUnitsMap = <String, String>{};
          for (final item in pack.items) {
            itemsMap[item.name] = item.quantityNum;
            itemUnitsMap[item.name] = item.unit;
          }

          // 1. Create Delivery Assignment
          await DeliveryService.createAssignment(
            familyId: family.id,
            familyArea: family.area,
            familyCity: family.city,
            familyAddress: family.address ?? '',
            familyPhone: family.phone,
            familySize: family.familySize,
            familyGeoLat: lat,
            familyGeoLng: lng,
            familyLocationVerified: locationVerified,
            assignedPackId: pack.id,
            assignedPackName: pack.name,
            items: itemsMap,
            itemUnits: itemUnitsMap,
            batch: batch,
          );

          // 2. Update family status
          batch.update(_firestore.collection('families').doc(familyId), {
            'fulfillmentStatus': 'stocked',
            'updatedAt': FieldValue.serverTimestamp(),
          });

          await batch.commit();

          // 3. Sync donations to in_process
          await ProcurementService._syncVerifiedDonationsToInProcess(familyId);

          await AuditService.logFamilyAction(
            action: 'Auto-Stocked (100% In-Kind)',
            familyId: familyId,
            familyName: family.area,
            details:
                'All items covered by In-Kind donations. Delivery assignment auto-created.',
          );

          return;
        }

        request = ProcurementRequest(
          id: '', // Auto-id
          familyId: family.id,
          familyAddress: family.area,
          packId: pack.id,
          packName: pack.name,
          category: 'Food',
          items: smartItems,
          budgetLimit: smartBudget,
          createdAt: DateTime.now(),
          status: ProcurementStatus.pending,
          inKindCoveredItems: coveredItems,
        );
      }

      await _firestore.collection(_collection).add(request.toFirestore());

      // Update family status
      await _firestore.collection('families').doc(familyId).update({
        'fulfillmentStatus': 'ready_for_purchase',
      });

      // Sync donations to in_process
      await ProcurementService._syncVerifiedDonationsToInProcess(familyId);

      // Notify all purchasers
      await NotificationService.notifyAllPurchasers(
        title: isMedicine
            ? 'New Medical Support Request 💊'
            : 'New Request Available 📦',
        message: isMedicine
            ? 'A medical prescription requires procurement in ${family.area}.'
            : 'A new pack "${request.packName}" is ready for purchase in ${family.area}.',
        actionType: 'new_request',
        actionId: family.id,
      );
    } catch (e) {
      debugPrint('Error generating procurement request: $e');
      rethrow;
    }
  }

  static Future<void> _syncVerifiedDonationsToInProcess(String familyId) async {
    await _syncDonationsToInProcess(
      familyId,
      fromStatuses: ['verified'], // FIX: Removed 'stocked' to prevent UI timeline regression for In-Kind donations
      note: 'Items are currently being purchased or prepared for delivery.',
    );
  }

  /// Generic helper to push donations from one or more statuses to `in_process`.
  static Future<void> _syncDonationsToInProcess(
    String familyId, {
    required List<String> fromStatuses,
    required String note,
  }) async {
    final snaps = await _firestore
        .collection('donations')
        .where('familyId', isEqualTo: familyId)
        .where('status', whereIn: fromStatuses)
        .get();

    if (snaps.docs.isEmpty) {
      await ProcurementService._syncParentSmartDonations(
        familyId,
        DonationStatus.inProcess.toFirestore(),
        note,
      );
      return;
    }

    final batch = _firestore.batch();
    for (final doc in snaps.docs) {
      final data = doc.data();
      
      // FIX: Never mutate In-Kind donations into `in_process`.
      // Procurement service is meant for processing Cash into goods.
      // In-Kind items bypass the shopping phase and simply wait as 'verified' or 'stocked'.
      if (data['donationType'] == 'inKind') continue;

      batch.update(doc.reference, {
        'status': DonationStatus.inProcess.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': DonationStatus.inProcess.toFirestore(),
            'timestamp': Timestamp.now(),
            'note': note,
          },
        ]),
      });
    }
    await batch.commit();

    await ProcurementService._syncParentSmartDonations(
      familyId,
      DonationStatus.inProcess.toFirestore(),
      note,
    );
  }



  /// Updates parent Smart Give donation when a family's slices advance.
  /// Only ever increases status — never regresses.
  static Future<void> _syncParentSmartDonations(
    String familyId,
    String newStatus,
    String note,
  ) async {
    const statusOrder = [
      'draft',
      'pending',
      'under_verification',
      'verified',
      'stocked',
      'in_process',
      'out_for_delivery',
      'delivered',
      'closed',
    ];
    final newIdx = statusOrder.indexOf(newStatus);
    if (newIdx < 0) return;

    // Find smart-split slices for this family
    final sliceSnaps = await _firestore
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
      final parentRef = _firestore.collection('donations').doc(parentId!);
      final parentDoc = await parentRef.get();
      if (!parentDoc.exists) continue;

      final currentStatus = parentDoc.data()?['status'] as String? ?? 'draft';
      final type = parentDoc.data()?['donationType'] as String?;

      // Ultimate safety firewall: Never arbitrarily drag In-Kind Smart Parents into "Purchasing/In Process"
      if (newStatus == 'in_process' && type == 'inKind') {
        continue;
      }

      final currentIdx = statusOrder.indexOf(currentStatus);
      // Never regress
      if (newIdx <= currentIdx) continue;

      await parentRef.update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          {'status': newStatus, 'timestamp': Timestamp.now(), 'note': note},
        ]),
      });
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

  /// Notify Admin about stale warehouse stock (> 7 days without delivery)
  static Future<void> notifyStaleWarehouseItems() async {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final snap = await _firestore
        .collection('warehouse_stock')
        .where('status', whereIn: ['pending_pickup', 'received'])
        .where('createdAt', isLessThan: Timestamp.fromDate(sevenDaysAgo))
        .get();

    if (snap.docs.isNotEmpty) {
      await NotificationService.sendAdminNotification(
        title: 'Stale Warehouse Stock Alert ⚠️',
        message:
            '${snap.docs.length} warehouse item batch(es) have been waiting over 7 days with no delivery assignment.',
        type: 'stale_stock',
      );
    }
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
    // Single Firestore query with OR filter (Firestore ^5.0.0+)
    return _firestore
        .collection(_collection)
        .where(
          Filter.or(
            Filter('claimedById', isEqualTo: purchaserId),
            Filter('purchaserId', isEqualTo: purchaserId),
          ),
        )
        .snapshots()
        .map((s) {
          final requests = s.docs
              .map(ProcurementRequest.fromFirestore)
              .toList();
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return requests;
        });
  }

  /// Smart UID-filtered history stream (Global if supervisor, personal if not)
  static Stream<List<ProcurementRequest>> getSmartHistoryStream(
    String purchaserId,
    bool isSupervisor,
  ) {
    // Expanded status list to include all post-purchase statuses
    const statuses = [
      'verified',
      'stocked',
      'in_transit',
      'delivered',
      'rejected',
      'issue_reported',
      'written_off',
    ];
    if (isSupervisor) {
      return _firestore
          .collection(_collection)
          .where('status', whereIn: statuses)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(ProcurementRequest.fromFirestore).toList());
    } else {
      return _firestore
          .collection(_collection)
          .where('purchaserId', isEqualTo: purchaserId)
          .where('status', whereIn: statuses)
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

      // Notify Admin that an order has been claimed
      final reqDoc = await ref.get();
      if (reqDoc.exists) {
        final familyArea = reqDoc.data()?['familyAddress'] ?? '';
        final packName = reqDoc.data()?['packName'] ?? '';
        final familyId = reqDoc.data()?['familyId'] as String?;
        await NotificationService.sendAdminNotification(
          title: 'Purchase Order Claimed 👤',
          message:
              '$purchaserName claimed the "$packName" purchase order for $familyArea.',
          type: 'order_claimed',
          relatedId: requestId,
        );
        // Fix #1: Purchaser claiming order → advance cash donations to in_process
        if (familyId != null && familyId.isNotEmpty) {
          await ProcurementService._syncDonationsToInProcess(
            familyId,
            fromStatuses: ['verified'],
            note: 'A purchaser is now procuring your ration pack items.',
          );
        }
      }

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
      final doc = await _firestore.collection(_collection).doc(requestId).get();
      if (!doc.exists) throw Exception('Purchase request not found');

      final requestData = doc.data() as Map<String, dynamic>;
      final budgetLimit =
          (requestData['budgetLimit'] as num?)?.toDouble() ?? 0.0;
      final maxAllowed = budgetLimit * 1.10;

      if (totalSpent > maxAllowed) {
        throw Exception(
          'Total spent (PKR ${totalSpent.toStringAsFixed(0)}) exceeds the maximum 10% inflation tolerance (PKR ${maxAllowed.toStringAsFixed(0)}). Please contact an Administrator to revise the budget.',
        );
      }

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

      // ProcurementItem.quantity remains a string for now, but we'll parse it cleanly
      // (ProcurementItem is separate from PackItem, we'll extract the number)
      final itemsMap = <String, num>{};
      final itemUnitsMap = <String, String>{};
      for (final item in request.items) {
        final qtyStr = RegExp(r'[\d.]+').stringMatch(item.quantity) ?? '1';
        itemsMap[item.name] = double.tryParse(qtyStr) ?? 1.0;
        itemUnitsMap[item.name] = item.unit;
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
        itemUnits: itemUnitsMap,
        inKindCoveredItems: request.inKindCoveredItems,
        procurementRequestId: requestId,
        batch: batch,
      );

      // 5. Update family status to stocked (visible in delivery module)
      batch.update(_firestore.collection('families').doc(request.familyId), {
        'fulfillmentStatus': 'stocked',
        'spentAmount': request.totalSpent,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 6. Central GRF Financial Reconciliation & Ledger Entry
      final variance = request.budgetLimit - request.totalSpent;
      if (variance != 0) {
        final grfRef = _firestore
            .collection('families')
            .doc('general_relief_fund');
        batch.update(grfRef, {'raisedAmount': FieldValue.increment(variance)});

        // Generate official GRF Audit transaction record
        final ledgerRef = _firestore.collection('donations').doc();
        batch.set(ledgerRef, {
          'donationId': ledgerRef.id,
          'amount': variance.abs(),
          'familyId': variance > 0 ? 'general_relief_fund' : request.familyId,
          'isGrfAllocation': variance < 0,
          'status': 'verified',
          'donorName': variance > 0
              ? 'Savings from ${request.packName}'
              : 'System',
          'donorEmail': 'system@rationaid.com',
          'allocatedByUid': 'system_reconciliation', // Represents System
          'donationNote': variance > 0
              ? 'Surplus Recovery'
              : 'Inflation Subsidy for ${request.packName}',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Commit the batch to ensure total atomicity
      await batch.commit();

      // Fix #2: adminVerifyPurchase → keep cash donations as 'in_process' until delivery
      // (We intentionally exclude 'stocked' here to protect the In-Kind donations from regressing)
      await ProcurementService._syncDonationsToInProcess(
        request.familyId,
        fromStatuses: ['verified', 'in_process'],
        note: 'Items successfully procured and queued for delivery to your family.',
      );

      // Send the GRF Audit notification if variance applies
      if (variance != 0) {
        await NotificationService.notifyAdminGRFSweep(
          amount: variance.abs(),
          isSurplus: variance > 0,
          packName: request.packName,
        );
      }

      // 7. Notify purchaser
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
