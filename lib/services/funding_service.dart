import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/services/notification_service.dart';

class FundingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Recalculate funding for a specific family based on verified donations
  static Future<void> recalculateFamilyFunding(String familyId) async {
    try {
      // 1. Get the family document
      final familyDoc = await _firestore
          .collection('families')
          .doc(familyId)
          .get();
      if (!familyDoc.exists) return;

      final familyData = familyDoc.data()!;
      final double targetAmount =
          (familyData['assignedPackBudget'] ?? familyData['targetAmount'] ?? 0)
              .toDouble();

      // 2. Get all VERIFIED donations for this family
      final donationsSnapshot = await _firestore
          .collection('donations')
          .where('familyId', isEqualTo: familyId)
          .where(
            'status',
            isEqualTo: 'verified',
          ) // Only count verified donations
          .get();

      // 3. Sum up the amounts
      double raisedAmount = 0;
      for (var doc in donationsSnapshot.docs) {
        final amount = (doc.data()['amount'] ?? 0).toDouble();
        raisedAmount += amount;
      }

      // 4. Determine status
      String fundingStatus = 'pending';
      if (raisedAmount >= targetAmount && targetAmount > 0) {
        fundingStatus = 'fully_funded';
      } else if (raisedAmount > 0) {
        fundingStatus = 'partially_funded';
      }

      // 5. Update family document
      final currentFulfillment = familyData['fulfillmentStatus'] ?? 'pending';
      String newFulfillment = currentFulfillment;

      // Auto-advance to ready_for_purchase if funded and currently pending
      if (fundingStatus == 'fully_funded' && currentFulfillment == 'pending') {
        newFulfillment = 'ready_for_purchase';
        // Notify Admins
        await NotificationService.notifyFullyFunded(familyId);
      }

      await _firestore.collection('families').doc(familyId).update({
        'targetAmount': targetAmount,
        'raisedAmount': raisedAmount,
        'remainingAmount': (targetAmount - raisedAmount).clamp(0, targetAmount),
        'fundingStatus': fundingStatus,
        'fulfillmentStatus': newFulfillment,
        'updatedAt': FieldValue.serverTimestamp(),
      });
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
        } else {
          await recalculateFamilyFunding(familyId);
        }
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
