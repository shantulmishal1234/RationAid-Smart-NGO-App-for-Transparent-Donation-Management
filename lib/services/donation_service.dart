import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/notification_service.dart';

/// Service for managing donations in Firestore
class DonationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a new donation
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
          userData?['name'] as String? ?? userData?['display_name'] as String?;
      final donorEmail = userData?['email'] as String?;

      // Debug: Print donor info (remove in production)
      print('Creating donation with donor info:');
      print('  donorId: ${donation.donorId}');
      print('  donorName: $donorName');
      print('  donorEmail: $donorEmail');

      // Create donation with donor information
      final donationWithDonorInfo = Donation(
        id: donation.id,
        donorId: donation.donorId,
        donorName: donorName,
        donorEmail: donorEmail,
        familyId: donation.familyId,
        donationType: donation.donationType,
        amount: donation.amount,
        items: donation.items,
        anonymous: donation.anonymous,
        status: donation.status,
        rejectionReason: donation.rejectionReason,
        paymentProofUrl: donation.paymentProofUrl,
        receiptUrl: donation.receiptUrl,
        donationNote: donation.donationNote,
        createdAt: donation.createdAt,
        updatedAt: donation.updatedAt,
        statusHistory: donation.statusHistory,
        estimatedDelivery: donation.estimatedDelivery,
        driverName: donation.driverName,
        driverPhone: donation.driverPhone,
        vehicleNumber: donation.vehicleNumber,
        deliveryPhotos: donation.deliveryPhotos,
        deliveredAt: donation.deliveredAt,
        receivedBy: donation.receivedBy,
      );

      final docRef = await _firestore
          .collection('donations')
          .add(donationWithDonorInfo.toFirestore());

      // Log audit trail
      await AuditService.logDonationAction(
        action: 'create_donation',
        donationId: docRef.id,
        details: 'Status: ${donation.status.toFirestore()}',
      );

      // Send notification to admins if submitted for verification
      if (donation.status == DonationStatus.underVerification) {
        await NotificationService.sendToRole(
          role: 'admin',
          title: 'New Donation Submitted',
          body:
              '${donorName ?? "A donor"} submitted a ${donation.donationType == DonationType.cash ? "Cash" : "In-Kind"} donation for verification',
          data: {
            'type': 'donation_submitted',
            'donationId': docRef.id,
            'route': '/admin/donations',
          },
        );
        print('Notification sent to admins for donation: ${docRef.id}');
      }

      return docRef.id;
    } catch (e) {
      print('Error creating donation: $e');
      throw Exception('Failed to create donation: $e');
    }
  }

  /// Update an existing donation
  Future<void> updateDonation(String donationId, Donation donation) async {
    try {
      // Get current donation to log before status
      final currentDoc = await _firestore
          .collection('donations')
          .doc(donationId)
          .get();
      final currentData = currentDoc.data();
      final beforeStatus = currentData?['status'] ?? '';

      await _firestore
          .collection('donations')
          .doc(donationId)
          .update(donation.toFirestore());

      // Log audit trail
      await AuditService.logDonationAction(
        action: 'update_donation',
        donationId: donationId,
        details: 'Status: $beforeStatus → ${donation.status.toFirestore()}',
      );

      // Notify admins if status changed to underVerification
      final afterStatus = donation.status.toFirestore();
      if (afterStatus == 'under_verification' &&
          (beforeStatus == 'draft' || beforeStatus == 'pending')) {
        final donorName = donation.donorName ?? 'A donor';
        await NotificationService.sendToRole(
          role: 'admin',
          title: 'Donation Submitted for Verification',
          body:
              '$donorName submitted a ${donation.donationType == DonationType.cash ? "Cash" : "In-Kind"} donation for verification',
          data: {
            'type': 'donation_submitted',
            'donationId': donationId,
            'route': '/admin/donations',
          },
        );
        print('Notification sent to admins for updated donation: $donationId');
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

      // Log audit trail
      await AuditService.logDonationAction(
        action: 'submit_for_verification',
        donationId: donationId,
        details: 'Status: ${data?['status'] ?? ''} → under_verification',
      );
    } catch (e) {
      throw Exception('Failed to submit for verification: $e');
    }
  }
}
