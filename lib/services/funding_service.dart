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

      // 2. Get all VERIFIED and PENDING donations for this family
      final donationsSnapshot = await _firestore
          .collection('donations')
          .where('familyId', isEqualTo: familyId)
          .where(
            'status',
            whereIn: ['verified', 'under_verification', 'pending'],
          ) // Count verified AND pending
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
        // In-Kind donations (only pending/under_verification count towards pendingNeeds)
        // For General Relief, we typically don't track specific "needs" decrement, but we track pending items
        else if (type == 'inKind' && items != null) {
          if (status == 'under_verification' || status == 'pending') {
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
      await _firestore.collection('families').doc(familyId).update({
        'raisedAmount': raisedAmount,
        'pendingAmount': pendingAmount,
        'remainingAmount': (targetAmount - raisedAmount).clamp(0, targetAmount),
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
        if (donationType == 'in_kind' && items != null) {
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
    if (familyId == 'general_relief_fund') return; // Skip for General Relief
    try {
      final familyRef = _firestore.collection('families').doc(familyId);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(familyRef);
        if (!snapshot.exists) throw Exception('Family not found');

        final data = snapshot.data()!;
        final Map<String, dynamic> currentNeeds = data['needs'] != null
            ? Map<String, dynamic>.from(data['needs'])
            : {};

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
