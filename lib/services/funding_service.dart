import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:ration_aid/services/procurement_service.dart';

class FundingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Recalculate funding for a specific family based on verified donations
  /// Recalculate funding for a specific family based on verified donations
  static Future<void> recalculateFamilyFunding(String familyId) async {
    // Note: We now process 'general_relief_fund' too!

    try {
      // 1. Get the family document
      DocumentSnapshot familyDoc = await _firestore
          .collection('families')
          .doc(familyId)
          .get();

      // Special handling for General Relief Fund if it doesn't exist yet
      if (!familyDoc.exists && familyId == 'general_relief_fund') {
        await _firestore.collection('families').doc(familyId).set({
          'area': 'General Relief Fund',
          'city': 'All',
          'targetAmount': 10000000.0, // Arbitrary high target for visuals
          'raisedAmount': 0.0,
          'status': 'accepted',
          'familySize': 0,
          'numberOfAdults': 0,
          'numberOfChildren': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
        familyDoc = await _firestore.collection('families').doc(familyId).get();
      } else if (!familyDoc.exists) {
        return; // Normal family not found
      }

      final familyData = familyDoc.data() as Map<String, dynamic>;
      final double targetAmount =
          (familyData['assignedPackBudget'] ?? familyData['targetAmount'] ?? 0)
              .toDouble();

      // 2. Get all VERIFIED and active donations for this family
      // Include all post-draft statuses so raisedAmount never drops as donation progresses
      final donationsSnapshot = await _firestore
          .collection('donations')
          .where('familyId', isEqualTo: familyId)
          .where(
            'status',
            whereIn: [
              'under_verification',
              'pending',
              'verified',
              'in_process',
              'out_for_delivery',
              'delivered',
              'closed',
            ],
          )
          .get();

      // 3. Sum up the amounts - Include Verified and Pending
      double raisedAmount = 0;
      double pendingAmount = 0;
      final Map<String, int> pendingNeeds = {};

      for (var doc in donationsSnapshot.docs) {
        final data = doc.data();
        final amount = (data['amount'] ?? 0).toDouble();
        final status = data['status'];
        final type = data['donationType'];
        final items = data['items'] as Map<String, dynamic>?;

        // Cash donations
        if (type == 'cash' || type == null) {
          if (status == 'verified') {
            raisedAmount += amount;
          } else if (status == 'under_verification' || status == 'pending') {
            pendingAmount += amount;
          }
        }
        // In-Kind donations
        else if (type == 'inKind') {
          // FEATURE: If admin assigned a declared monetary value, count it in raisedAmount
          if (status == 'verified' && amount > 0) {
            raisedAmount += amount;
          } else if ((status == 'under_verification' || status == 'pending') &&
              amount > 0) {
            pendingAmount += amount;
          }
          // Track pending item needs (always, regardless of amount)
          if ((status == 'under_verification' || status == 'pending') &&
              items != null) {
            items.forEach((item, quantity) {
              final qty = (quantity as num).toInt();
              pendingNeeds[item] = (pendingNeeds[item] ?? 0) + qty;
            });
          }
        }
      }

      // 4. Determine status
      String fundingStatus = 'pending';
      final totalFunded = raisedAmount + pendingAmount;

      if (targetAmount > 0 && totalFunded >= targetAmount) {
        fundingStatus = 'fully_funded';
      } else if (totalFunded > 0) {
        fundingStatus = 'partially_funded';
      }

      // For General Relief, status is always just 'collecting' or 'active', but let's keep standard fields
      if (familyId == 'general_relief_fund') {
        fundingStatus = 'active_pool';
      }

      // 5. Update family document first with all new stats
      final double surplusAmount = (raisedAmount - targetAmount).clamp(
        0,
        double.infinity,
      );

      await _firestore.collection('families').doc(familyId).update({
        'raisedAmount': raisedAmount,
        'pendingAmount': pendingAmount,
        'remainingAmount': (targetAmount - raisedAmount).clamp(0, targetAmount),
        'surplusAmount': surplusAmount,
        'pendingNeeds': pendingNeeds,
        'fundingStatus': fundingStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        // Ensure standard fields exist for General Relief if missing
        if (familyId == 'general_relief_fund') ...{
          'targetAmount': targetAmount, // Persist the target
        },
      });

      // 6. Trigger Procurement if needed
      // Skip procurement for General Relief Fund as it's a pool, not a specific family pack
      if (familyId != 'general_relief_fund') {
        final currentFulfillment = familyData['fulfillmentStatus'] ?? 'pending';

        if (fundingStatus == 'fully_funded' &&
            currentFulfillment == 'pending') {
          // The family is newly fully funded.
          await ProcurementService.checkAndGenerateRequest(familyId);
        }
      }
    } catch (e) {
      print('Error recalculating funding for family $familyId: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PHASE 10: Pool Management Methods
  // ─────────────────────────────────────────────────────────────────────────

  /// Allocate funds from the General Relief Fund pool to a specific family.
  /// Creates a verified pseudo-donation (donorId: 'grf_allocation') and
  /// triggers recalculation on both the GRF pool and the target family.
  static Future<void> allocateFromGRF({
    required String targetFamilyId,
    required double amount,
    String adminNote = 'Allocated from General Relief Fund',
    String? adminUid,
  }) async {
    if (amount <= 0)
      throw Exception('Allocation amount must be greater than 0');
    if (targetFamilyId == 'general_relief_fund') {
      throw Exception('Cannot allocate GRF funds to itself');
    }

    try {
      // 1. Verify GRF has enough balance
      final grfDoc = await _firestore
          .collection('families')
          .doc('general_relief_fund')
          .get();
      if (!grfDoc.exists) throw Exception('General Relief Fund not found');
      final grfData = grfDoc.data()!;
      final grfRaised = (grfData['raisedAmount'] ?? 0).toDouble();

      if (grfRaised < amount) {
        throw Exception(
          'Insufficient GRF balance. Available: PKR ${grfRaised.toStringAsFixed(0)}',
        );
      }

      // 2. Create a verified pseudo-donation from GRF → family
      final donationRef = _firestore.collection('donations').doc();
      await donationRef.set({
        'donorId': 'grf_allocation',
        'donorName': 'General Relief Fund',
        'donorEmail': null,
        'familyId': targetFamilyId,
        'donationType': 'cash',
        'amount': amount,
        'status': 'verified',
        'anonymous': false,
        'donationNote': adminNote,
        'allocatedByUid': adminUid,
        'isGrfAllocation': true, // flag to identify this type
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': [
          {
            'status': 'verified',
            'timestamp': Timestamp.now(),
            'note': 'GRF allocation by admin',
          },
        ],
      });

      // 3. Deduct from GRF raisedAmount directly
      await _firestore
          .collection('families')
          .doc('general_relief_fund')
          .update({
            'raisedAmount': FieldValue.increment(-amount),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // 4. Recalculate both sides
      await recalculateFamilyFunding(targetFamilyId);
      await recalculateFamilyFunding('general_relief_fund');

      print('GRF allocation of PKR $amount to $targetFamilyId complete');
    } catch (e) {
      print('Error allocating from GRF: $e');
      rethrow;
    }
  }

  /// Transfer surplus from an over-funded family to another family or back to GRF.
  /// [fromFamilyId] must have surplusAmount >= amount.
  /// [toFamilyId] can be any family ID or 'general_relief_fund'.
  static Future<void> transferSurplus({
    required String fromFamilyId,
    required String toFamilyId,
    required double amount,
    String adminNote = 'Surplus transfer',
    String? adminUid,
  }) async {
    if (amount <= 0) throw Exception('Transfer amount must be greater than 0');
    if (fromFamilyId == toFamilyId)
      throw Exception('Cannot transfer to same family');

    try {
      // 1. Verify source has enough surplus
      final srcDoc = await _firestore
          .collection('families')
          .doc(fromFamilyId)
          .get();
      if (!srcDoc.exists) throw Exception('Source family not found');
      final srcData = srcDoc.data()!;
      final srcSurplus = (srcData['surplusAmount'] ?? 0).toDouble();

      if (srcSurplus < amount) {
        throw Exception(
          'Insufficient surplus. Available: PKR ${srcSurplus.toStringAsFixed(0)}',
        );
      }

      // 2. Create a transfer record for auditing
      await _firestore.collection('pool_transfers').add({
        'fromFamilyId': fromFamilyId,
        'toFamilyId': toFamilyId,
        'amount': amount,
        'note': adminNote,
        'adminUid': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'surplus_transfer',
      });

      // 3. Create a verified pseudo-donation for the destination
      await _firestore.collection('donations').add({
        'donorId': 'surplus_transfer',
        'donorName': 'Surplus Transfer',
        'donorEmail': null,
        'familyId': toFamilyId,
        'donationType': 'cash',
        'amount': amount,
        'status': 'verified',
        'anonymous': false,
        'donationNote': '$adminNote (from family $fromFamilyId)',
        'allocatedByUid': adminUid,
        'isSurplusTransfer': true,
        'sourceFamilyId': fromFamilyId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': [
          {
            'status': 'verified',
            'timestamp': Timestamp.now(),
            'note': 'Surplus transfer from $fromFamilyId',
          },
        ],
      });

      // 4. Deduct from source family's raisedAmount (reducing effective surplus)
      await _firestore.collection('families').doc(fromFamilyId).update({
        'raisedAmount': FieldValue.increment(-amount),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 5. Recalculate both sides
      await recalculateFamilyFunding(fromFamilyId);
      await recalculateFamilyFunding(toFamilyId);

      print(
        'Surplus transfer of PKR $amount from $fromFamilyId to $toFamilyId complete',
      );
    } catch (e) {
      print('Error transferring surplus: $e');
      rethrow;
    }
  }

  /// Get overall funding statistics for Admin Dashboard
  static Stream<Map<String, double>> getFundingStatsStream() {
    return _firestore
        .collection('families')
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((snapshot) {
          double totalTarget = 0;
          double totalRaised = 0;

          for (var doc in snapshot.docs) {
            final data = doc.data();
            totalTarget += (data['targetAmount'] ?? 0).toDouble();
            totalRaised += (data['raisedAmount'] ?? 0).toDouble();
          }

          return {
            'totalTarget': totalTarget,
            'totalRaised': totalRaised,
            'totalGap': totalTarget - totalRaised,
          };
        });
  }

  /// Verify a donation and trigger funding recalculation
  static Future<void> verifyDonation(String donationId) async {
    try {
      final donationDoc = await _firestore
          .collection('donations')
          .doc(donationId)
          .get();
      if (!donationDoc.exists) throw Exception('Donation not found');

      final donationData = donationDoc.data()!;
      final String familyId = donationData['familyId'] ?? '';
      final String donationType = donationData['donationType'] ?? 'cash';
      final Map<String, dynamic>? items = donationData['items'];

      // Update donation status to verified
      await _firestore.collection('donations').doc(donationId).update({
        'status': DonationStatus.verified.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          StatusHistoryEntry(
            status: DonationStatus.verified,
            timestamp: DateTime.now(),
            note: 'Verified by system/admin',
          ).toMap(),
        ]),
      });

      // Recalculate family funding or process items if linked to a family
      if (familyId.isNotEmpty) {
        // FIX: donationType stored as 'inKind' (camelCase), NOT 'in_kind'
        if (donationType == 'inKind' && items != null) {
          await _processInKindDonation(familyId, Map<String, int>.from(items));
        }
        // Always recalculate to update pending amounts and needs
        await recalculateFamilyFunding(familyId);
      }
    } catch (e) {
      print('Error verifying donation: $e');
      rethrow;
    }
  }

  /// Process In-Kind donation: Decrement family needs and remove fulfilled items
  static Future<void> _processInKindDonation(
    String familyId,
    Map<String, int> donatedItems,
  ) async {
    // if (familyId == 'general_relief_fund') return; // Removed to allow tracking
    try {
      final familyRef = _firestore.collection('families').doc(familyId);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(familyRef);
        if (!snapshot.exists) throw Exception('Family not found');

        final data = snapshot.data()!;
        final Map<String, dynamic> currentNeeds = data['needs'] != null
            ? Map<String, dynamic>.from(data['needs'])
            : {};

        // Special process for General Relief Fund: Aggregate items, don't decrement needs
        if (familyId == 'general_relief_fund') {
          final Map<String, dynamic> collectedItems =
              data['collectedItems'] != null
              ? Map<String, dynamic>.from(data['collectedItems'])
              : {};

          donatedItems.forEach((item, quantity) {
            collectedItems[item] =
                (collectedItems[item] as int? ?? 0) + quantity;
          });

          transaction.update(familyRef, {
            'collectedItems': collectedItems,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }

        bool needsUpdated = false;

        // Decrement needs based on donated items
        donatedItems.forEach((item, quantity) {
          if (currentNeeds.containsKey(item)) {
            final currentQty = (currentNeeds[item] as num).toInt();
            final newQty = currentQty - quantity;

            if (newQty <= 0) {
              currentNeeds.remove(item);
            } else {
              currentNeeds[item] = newQty;
            }
            needsUpdated = true;
          }
        });

        if (needsUpdated) {
          // Check if all needs are fulfilled
          final isFullyFunded = currentNeeds.isEmpty;
          final fulfillmentStatus = isFullyFunded
              ? 'ready_for_purchase'
              : (data['fulfillmentStatus'] ?? 'pending');

          transaction.update(familyRef, {
            'needs': currentNeeds,
            'fulfillmentStatus': fulfillmentStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          if (isFullyFunded) {
            // Notify via NotificationService (fire and forget outside transaction)
            NotificationService.notifyFullyFunded(familyId);
          }
        }
      });
    } catch (e) {
      print('Error processing in-kind donation for family $familyId: $e');
      rethrow;
    }
  }
}
