import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/models/assistance_pack_model.dart';
import 'package:ration_aid/services/audit_service.dart';

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

      // Check existing
      final existingQuery = await _firestore
          .collection(_collection)
          .where('familyId', isEqualTo: familyId)
          .where('status', whereIn: ['pending', 'purchased', 'verified'])
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
        budgetLimit: family.targetAmount,
        createdAt: DateTime.now(),
        status: ProcurementStatus.pending,
      );

      await _firestore.collection(_collection).add(request.toFirestore());

      // Update family status
      await _firestore.collection('families').doc(familyId).update({
        'fulfillmentStatus': 'ready_for_purchase',
      });
    } catch (e) {
      print('Error generating procurement request: $e');
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
        .where('status', isEqualTo: 'verified') // Verified means stocked
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

  /// Purchaser submits purchase (receipt upload)
  static Future<void> submitPurchase({
    required String requestId,
    required String purchaserId,
    required String purchaserName,
    required String receiptUrl,
    required double totalSpent,
    required List<ProcurementItem> updatedItems,
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

      await AuditService.logAction(
        action: 'submit_purchase',
        entityType: 'procurement',
        entityId: requestId,
        details: 'Purchaser submitted purchase for review',
      );
    } catch (e) {
      print('Error submitting purchase: $e');
      rethrow;
    }
  }

  /// Admin verifies purchase (Stock In)
  static Future<void> adminVerifyPurchase(String requestId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(requestId).get();
      final request = ProcurementRequest.fromFirestore(doc);

      // Verify Logic: Deduct form budget if we were tracking global budget,
      // but here we just mark as verified/stocked.

      await _firestore.collection(_collection).doc(requestId).update({
        'status': 'verified',
        'verifiedAt': FieldValue.serverTimestamp(),
      });

      // Update Family
      await _firestore.collection('families').doc(request.familyId).update({
        'fulfillmentStatus': 'stocked',
        'spentAmount': request.totalSpent,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await AuditService.logAction(
        action: 'verify_purchase',
        entityType: 'procurement',
        entityId: requestId,
        details: 'Admin verified purchase. Stock added to inventory.',
      );
    } catch (e) {
      print('Error verifying purchase: $e');
      rethrow;
    }
  }

  /// Admin rejects purchase
  static Future<void> adminRejectPurchase(
    String requestId,
    String reason,
  ) async {
    try {
      await _firestore.collection(_collection).doc(requestId).update({
        'status': 'rejected',
        'adminRemarks': reason,
      });

      await AuditService.logAction(
        action: 'reject_purchase',
        entityType: 'procurement',
        entityId: requestId,
        details: 'Admin rejected purchase: $reason',
      );
    } catch (e) {
      print('Error rejecting purchase: $e');
      rethrow;
    }
  }
}
