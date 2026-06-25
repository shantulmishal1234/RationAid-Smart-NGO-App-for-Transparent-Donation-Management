import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/funding_service.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:uuid/uuid.dart';

/// Service for managing donations in Firestore
class DonationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a new donation.
  ///
  /// Cash donations are routed through `FundingService.submitAtomicDonation()`
  /// for atomic idempotency, cap enforcement, overflow routing, and ledger update.
  /// In-kind donations use the direct Firestore path (no monetary cap needed).
  Future<String> createDonation(Donation donation) async {
    try {
      // Fetch donor information from users collection
      final userDoc = await _firestore
          .collection('users')
          .doc(donation.donorId)
          .get();

      if (!userDoc.exists) {
        throw Exception(
          'User document not found for donorId: ${donation.donorId}',
        );
      }

      final userData = userDoc.data();
      final donorName =
          userData?['name'] as String? ??
          userData?['display_name'] as String? ??
          'Anonymous';
      final donorEmail = userData?['email'] as String? ?? '';

      // ── Cash donations → atomic engine ────────────────────────────────
      if (donation.donationType == DonationType.cash &&
          donation.status != DonationStatus.draft) {
        if (donation.familyId.isEmpty) {
          throw Exception(
            'Cash donation must have a target family (or general_relief_fund)',
          );
        }

        // Generate idempotency key if not set
        final idempotencyKey = donation.idempotencyKey.isNotEmpty
            ? donation.idempotencyKey
            : const Uuid().v4();

        final result = await FundingService.submitAtomicDonation(
          donorId: donation.donorId,
          donorName: donorName,
          donorEmail: donorEmail,
          targetFamilyId: donation.familyId,
          amount: donation.amount ?? 0,
          allocationMode: donation.allocationMode.isNotEmpty
              ? donation.allocationMode
              : 'direct',
          idempotencyKey: idempotencyKey,
          anonymous: donation.anonymous,
          donationNote: donation.donationNote,
          paymentProofUrl: donation.paymentProofUrl,
        );

        // Log audit trail
        await AuditService.logDonationAction(
          action: 'create_donation',
          donationId: result.donationId,
          details:
              'Mode: ${donation.allocationMode} | Amount: ${donation.amount} | Effective: ${result.effectiveAmount} | Overflow: ${result.overflowAmount}',
        );

        // Notify admins
        if (donation.status == DonationStatus.underVerification) {
          await NotificationService.sendToRole(
            role: 'admin',
            title: 'New Cash Donation Submitted',
            body: '$donorName submitted a Cash donation for verification',
            data: {
              'type': 'donation_submitted',
              'donationId': result.donationId,
              'route': '/admin/donations',
            },
          );
        }

        return result.donationId;
      }

      // ── In-kind / draft donations → direct path ───────────────────────
      final donationWithDonorInfo = Donation(
        id: donation.id,
        donorId: donation.donorId,
        donorName: donorName,
        donorEmail: donorEmail,
        familyId: donation.familyId,
        donationType: donation.donationType,
        amount: donation.amount,
        items: donation.items,
        // BUG FIX — itemUnits and smartSplits were previously dropped here,
        // causing in-kind split docs to never be created during pickup collection.
        itemUnits: donation.itemUnits,
        smartSplits: donation.smartSplits,
        anonymous: donation.anonymous,
        status: donation.status,
        rejectionReason: donation.rejectionReason,
        paymentProofUrl: donation.paymentProofUrl,
        receiptUrl: donation.receiptUrl,
        donationNote: donation.donationNote,
        createdAt: donation.createdAt,
        updatedAt: donation.updatedAt,
        pickupAddress: donation.pickupAddress,
        contactNumber: donation.contactNumber,
        statusHistory: donation.statusHistory,
        allocationMode: donation.allocationMode.isNotEmpty
            ? donation.allocationMode
            : 'direct',
        effectiveAmount: donation.amount ?? 0,
        overflowAmount: 0,
        idempotencyKey: donation.idempotencyKey.isNotEmpty
            ? donation.idempotencyKey
            : const Uuid().v4(),
      );

      final docRef = await _firestore
          .collection('donations')
          .add(donationWithDonorInfo.toFirestore());

      // Recalculate only for in-kind non-draft
      if (donation.familyId.isNotEmpty &&
          donation.status != DonationStatus.draft) {
        await FundingService.recalculateFamilyFunding(donation.familyId);
      }

      // Log audit trail
      await AuditService.logDonationAction(
        action: 'create_donation',
        donationId: docRef.id,
        details: 'Status: ${donation.status.toFirestore()}',
      );

      // Notify admins for in-kind verification
      if (donation.status == DonationStatus.underVerification) {
        await NotificationService.sendToRole(
          role: 'admin',
          title: 'New In-Kind Donation Submitted',
          body: '$donorName submitted an In-Kind donation for verification',
          data: {
            'type': 'donation_submitted',
            'donationId': docRef.id,
            'route': '/admin/donations',
          },
        );
      }

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create donation: $e');
    }
  }

  /// Update an existing donation.
  ///
  /// Fix #15: mutation of verified/in-process/delivered donations is blocked.
  /// Fix #5: cash draft → under_verification goes through submitAtomicDonation.
  Future<void> updateDonation(String donationId, Donation donation) async {
    try {
      // Get current donation to log before status
      final currentDoc = await _firestore
          .collection('donations')
          .doc(donationId)
          .get();
      final currentData = currentDoc.data();
      final beforeStatus = currentData?['status'] ?? '';

      // Fix #15 — block mutation of immutable states
      const immutableStatuses = [
        'verified',
        'in_process',
        'out_for_delivery',
        'delivered',
        'closed',
      ];
      if (immutableStatuses.contains(beforeStatus)) {
        throw Exception(
          'Cannot modify a donation in "$beforeStatus" state. '
          'Only draft or under_verification donations can be edited.',
        );
      }

      final afterStatus = donation.status.toFirestore();

      // Fix #5 — route cash draft→under_verification through the atomic engine
      // so correct cap + idempotency logic runs, not recalculateFamilyFunding().
      if (donation.donationType == DonationType.cash &&
          beforeStatus == 'draft' &&
          afterStatus == 'under_verification') {
        final userDoc = await _firestore
            .collection('users')
            .doc(donation.donorId)
            .get();
        final userData = userDoc.data();
        final donorName =
            userData?['name'] as String? ??
            userData?['display_name'] as String? ??
            donation.donorName ??
            'Anonymous';
        final donorEmail =
            userData?['email'] as String? ?? donation.donorEmail ?? '';

        // Delete the draft document first (atomic engine writes a new one)
        await _firestore.collection('donations').doc(donationId).delete();

        final idempotencyKey = donation.idempotencyKey.isNotEmpty
            ? donation.idempotencyKey
            : const Uuid().v4();

        final result = await FundingService.submitAtomicDonation(
          donorId: donation.donorId,
          donorName: donorName,
          donorEmail: donorEmail,
          targetFamilyId: donation.familyId,
          amount: donation.amount ?? 0,
          allocationMode: donation.allocationMode.isNotEmpty
              ? donation.allocationMode
              : 'direct',
          idempotencyKey: idempotencyKey,
          anonymous: donation.anonymous,
          donationNote: donation.donationNote,
          paymentProofUrl: donation.paymentProofUrl,
        );

        await AuditService.logDonationAction(
          action: 'submit_draft_donation',
          donationId: result.donationId,
          details:
              'Draft submitted atomically | Effective: ${result.effectiveAmount} | Overflow: ${result.overflowAmount}',
        );
        return;
      }

      // Standard update path (non-cash or re-upload of rejected)
      await _firestore
          .collection('donations')
          .doc(donationId)
          .update(donation.toFirestore());

      if (donation.familyId.isNotEmpty &&
          donation.status != DonationStatus.draft) {
        await FundingService.recalculateFamilyFunding(donation.familyId);
      }

      // Log audit trail
      await AuditService.logDonationAction(
        action: 'update_donation',
        donationId: donationId,
        details: 'Status: $beforeStatus → ${donation.status.toFirestore()}',
      );

      // Notify admins if status changed to underVerification
      if (afterStatus == 'under_verification' &&
          (beforeStatus == 'draft' || beforeStatus == 'pending')) {
        final donorName = donation.donorName ?? 'A donor';
        await NotificationService.sendToRole(
          role: 'admin',
          title: 'Donation Submitted for Verification',
          body:
              '$donorName submitted a ${donation.donationType == DonationType.cash ? 'Cash' : 'In-Kind'} donation for verification',
          data: {
            'type': 'donation_submitted',
            'donationId': donationId,
            'route': '/admin/donations',
          },
        );
      }

      // Notify Donor of status changes
      if (afterStatus != beforeStatus) {
        String? title;
        String? body;
        // Fix #17 — actionable rejection notification with amount and reason
        final rawAmount = currentData?['amount'];
        final amountStr = rawAmount != null
            ? 'PKR ${(num.tryParse(rawAmount.toString()) ?? 0).toStringAsFixed(0)}'
            : 'your';
        final donType = currentData?['donationType'] == 'inKind'
            ? 'in-kind'
            : 'cash';
        final rejectionReason = currentData?['rejectionReason'] as String?;

        switch (afterStatus) {
          case 'verified':
            title = 'Donation Verified! ✅';
            body =
                'Your $amountStr $donType donation has been verified. Thank you!';
            break;
          case 'rejected':
            title = 'Action Required ⚠️';
            body = rejectionReason != null
                ? 'Your $amountStr $donType donation was rejected. Reason: $rejectionReason'
                : 'Your $amountStr $donType donation was rejected. Please check the app for details.';
            break;
          case 'stocked':
            title = 'Items Arrived at Warehouse! 📦';
            body =
                'Your donated items have been collected and are now safely stored in our warehouse. Delivery will be arranged soon.';
            break;
          case 'in_process':
            title = 'Items Being Purchased! 🛒';
            body =
                'Great news! Your $amountStr donation is being used to purchase ration items for the family.';
            break;
          case 'out_for_delivery':
            title = 'On the Way! 🚚';
            body = 'Your donation is out for delivery to the family. Almost there!';
            break;
          case 'delivered':
            title = 'Impact Made! ❤️';
            body =
                'Your $amountStr donation has been delivered. Thank you for making a difference!';
            break;
          case 'pool_assigned':
            title = 'In-Kind Items Assigned to a Family! 📦';
            body =
                'Your donated items have been matched and reserved for a family in need.';
            break;
          case 'cancelled':
            title = 'Donation Cancelled';
            body = 'Your $amountStr $donType donation has been cancelled.';
            break;
        }

        if (title != null && body != null) {
          final donorId = currentData?['donorId'] as String?;
          if (donorId != null) {
            await NotificationService.sendDonorNotification(
              userId: donorId,
              title: title,
              message: body,
              actionType: 'donation_update',
              actionId: donationId,
            );
          }
        }
      }
    } catch (e) {
      throw Exception('Failed to update donation: $e');
    }
  }

  /// Delete a donation (only drafts)
  Future<void> deleteDonation(String donationId) async {
    try {
      // Verify it's a draft before deleting
      final doc = await _firestore
          .collection('donations')
          .doc(donationId)
          .get();
      final data = doc.data();

      if (data?['status'] != 'draft') {
        throw Exception('Only draft donations can be deleted');
      }

      await _firestore.collection('donations').doc(donationId).delete();

      // Log audit trail
      await AuditService.logDonationAction(
        action: 'delete_donation',
        donationId: donationId,
        details: 'Deleted draft donation',
      );
    } catch (e) {
      throw Exception('Failed to delete donation: $e');
    }
  }

  /// Re-upload payment proof for rejected donations
  Future<void> reuploadPaymentProof(
    String donationId,
    String newPaymentProofUrl,
  ) async {
    try {
      // Verify it's rejected before allowing reupload
      final doc = await _firestore
          .collection('donations')
          .doc(donationId)
          .get();
      final data = doc.data();

      if (data?['status'] != 'rejected') {
        throw Exception('Only rejected donations can be re-uploaded');
      }

      await _firestore.collection('donations').doc(donationId).update({
        'paymentProofUrl': newPaymentProofUrl,
        'status': 'under_verification',
        'rejectionReason': null,
        'updatedAt': Timestamp.now(),
      });

      // Log audit trail
      await AuditService.logDonationAction(
        action: 'reupload_payment_proof',
        donationId: donationId,
        details: 'Status: rejected → under_verification',
      );

      // Notify admin that proof has been re-submitted
      final donorName = data?['donorName'] ?? 'A donor';
      final donType = data?['donationType'] == 'inKind' ? 'In-Kind' : 'Cash';
      await NotificationService.sendAdminNotification(
        title: 'Proof Re-Submitted 🔄',
        message:
            '$donorName has re-uploaded proof for a rejected $donType donation. Review required.',
        type: 'donation_resubmitted',
        relatedId: donationId,
      );
    } catch (e) {
      throw Exception('Failed to reupload payment proof: $e');
    }
  }

  /// Stream donations by donor ID
  Stream<List<Donation>> streamDonationsByDonor(String donorId) {
    return _firestore
        .collection('donations')
        .where('donorId', isEqualTo: donorId)
        .orderBy('createdAt', descending: true)
        .limit(200) // Cap to prevent unbounded reads at scale
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Donation.fromFirestore(doc))
              .toList();
        });
  }

  /// Stream recent donations by donor ID with limit
  Stream<List<Donation>> streamRecentDonationsByDonor(
    String donorId, {
    int limit = 5,
  }) {
    return _firestore
        .collection('donations')
        .where('donorId', isEqualTo: donorId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Donation.fromFirestore(doc))
              .toList();
        });
  }

  /// Stream donations by donor ID with status filter
  Stream<List<Donation>> streamDonationsByDonorAndStatus(
    String donorId,
    DonationStatus status,
  ) {
    return _firestore
        .collection('donations')
        .where('donorId', isEqualTo: donorId)
        .where('status', isEqualTo: status.toFirestore())
        .orderBy('createdAt', descending: true)
        .limit(100) // Cap to prevent unbounded reads at scale
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Donation.fromFirestore(doc))
              .toList();
        });
  }

  /// Get single donation by ID
  Future<Donation?> getDonationById(String donationId) async {
    try {
      final doc = await _firestore
          .collection('donations')
          .doc(donationId)
          .get();
      if (!doc.exists) return null;
      return Donation.fromFirestore(doc);
    } catch (e) {
      throw Exception('Failed to get donation: $e');
    }
  }

  /// Get donation statistics for a donor
  Future<Map<String, int>> getDonorStats(String donorId) async {
    try {
      final snapshot = await _firestore
          .collection('donations')
          .where('donorId', isEqualTo: donorId)
          .get();

      final donations = snapshot.docs
          .map((doc) => Donation.fromFirestore(doc))
          .toList();

      // Count unique families
      final familiesSupported = donations.map((d) => d.familyId).toSet().length;

      // Count active donations (verified, in_process, out_for_delivery)
      final activeDonations = donations
          .where(
            (d) =>
                d.status == DonationStatus.verified ||
                d.status == DonationStatus.inProcess ||
                d.status == DonationStatus.outForDelivery,
          )
          .length;

      // Count completed (delivered + closed)
      final completedDeliveries = donations
          .where(
            (d) =>
                d.status == DonationStatus.delivered ||
                d.status == DonationStatus.closed,
          )
          .length;

      return {
        'total': donations.length,
        'families': familiesSupported,
        'active': activeDonations,
        'completed': completedDeliveries,
      };
    } catch (e) {
      throw Exception('Failed to get donor stats: $e');
    }
  }

  /// Get recent donations for dashboard (last 5)
  Future<List<Donation>> getRecentDonations(String donorId) async {
    try {
      final snapshot = await _firestore
          .collection('donations')
          .where('donorId', isEqualTo: donorId)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();

      return snapshot.docs.map((doc) => Donation.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('Failed to get recent donations: $e');
    }
  }

  /// Submit donation for verification (change status from draft to under_verification)
  Future<void> submitForVerification(String donationId) async {
    try {
      final doc = await _firestore
          .collection('donations')
          .doc(donationId)
          .get();
      final data = doc.data();

      if (data?['status'] != 'draft' && data?['status'] != 'pending') {
        throw Exception('Only draft or pending donations can be submitted');
      }

      await _firestore.collection('donations').doc(donationId).update({
        'status': 'under_verification',
        'updatedAt': Timestamp.now(),
      });

      // Note: No recalculateFamilyFunding() here — status change doesn't
      // alter financial amounts. Funding is handled atomically at creation.

      // Log audit trail
      await AuditService.logDonationAction(
        action: 'submit_for_verification',
        donationId: donationId,
        details: 'Status: ${data?['status'] ?? ''} → under_verification',
      );

      // Notify admins
      final donorName = data?['donorName'] ?? 'A donor';
      final type = data?['donationType'] ?? 'Unknown';

      await NotificationService.sendToRole(
        role: 'admin',
        title: 'Donation Submitted for Verification',
        body: '$donorName submitted a $type donation for verification',
        data: {
          'type': 'donation_submitted',
          'donationId': donationId,
          'route': '/admin/donations',
        },
      );
    } catch (e) {
      throw Exception('Failed to submit for verification: $e');
    }
  }

  /// Stream donation statistics for a donor
  Stream<Map<String, int>> streamDonorStats(String donorId) {
    return _firestore
        .collection('donations')
        .where('donorId', isEqualTo: donorId)
        .snapshots()
        .map((snapshot) {
          final donations = snapshot.docs
              .map((doc) => Donation.fromFirestore(doc))
              .toList();

          final familiesSupported = donations
              .map((d) => d.familyId)
              .toSet()
              .length;

          final activeDonations = donations
              .where(
                (d) =>
                    d.status == DonationStatus.verified ||
                    d.status == DonationStatus.inProcess ||
                    d.status == DonationStatus.outForDelivery,
              )
              .length;

          final completedDeliveries = donations
              .where(
                (d) =>
                    d.status == DonationStatus.delivered ||
                    d.status == DonationStatus.closed,
              )
              .length;

          return {
            'total': donations.length,
            'families': familiesSupported,
            'active': activeDonations,
            'completed': completedDeliveries,
          };
        });
  }

  /// Stream a single donation by ID
  Stream<Donation?> streamDonation(String donationId) {
    return _firestore.collection('donations').doc(donationId).snapshots().map((
      doc,
    ) {
      if (!doc.exists) return null;
      return Donation.fromFirestore(doc);
    });
  }

  /// Stream the latest active donation for a donor.
  ///
  /// Fix #1: Uses server-side `whereIn` + `.limit(1)` to avoid full-collection
  /// scan. Requires a composite Firestore index:
  ///   donations → donorId ASC, status ASC, updatedAt DESC
  Stream<Donation?> streamActiveDonation(String donorId) {
    const activeStatuses = [
      'pending',
      'under_verification',
      'verified',
      'in_process',
      'out_for_delivery',
    ];
    return _firestore
        .collection('donations')
        .where('donorId', isEqualTo: donorId)
        .where('status', whereIn: activeStatuses)
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          return Donation.fromFirestore(snapshot.docs.first);
        });
  }

  /// Stream comprehensive metrics for donor dashboard with a cap.
  /// Reads at most 500 docs — sufficient for any realistic donor history.
  Stream<Map<String, dynamic>> streamDonorStatsAdvanced(String donorId) {
    return _firestore
        .collection('donations')
        .where('donorId', isEqualTo: donorId)
        .orderBy('createdAt', descending: true)
        .limit(500)
        .snapshots()
        .map((snapshot) {
          final donations = snapshot.docs
              .map((doc) => Donation.fromFirestore(doc))
              .toList();
          
          double totalAmount = 0;
          for (var d in donations) {
             totalAmount += (d.amount ?? 0);
          }

          final familiesSupported = donations
              .map((d) => d.familyId)
              .where((id) => id.isNotEmpty && id != 'general_relief_fund')
              .toSet()
              .length;
          final activeDonations = donations
              .where(
                (d) =>
                    d.status == DonationStatus.verified ||
                    d.status == DonationStatus.inProcess ||
                    d.status == DonationStatus.outForDelivery,
              )
              .length;
          final completedDeliveries = donations
              .where(
                (d) =>
                    d.status == DonationStatus.delivered ||
                    d.status == DonationStatus.closed,
              )
              .length;
          return {
            'total': donations.length,
            'families': familiesSupported,
            'active': activeDonations,
            'completed': completedDeliveries,
            'totalAmount': totalAmount,
          };
        });
  }
}
