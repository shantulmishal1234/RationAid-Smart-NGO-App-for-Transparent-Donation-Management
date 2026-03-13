import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ration_aid/models/family_review_model.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/notification_service.dart';

/// Service for managing family review workflow (quorum-based voting)
class FamilyReviewService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Submit a vote for a family
  /// Returns true if successful, false if user already voted
  static Future<bool> submitVote({
    required String familyId,
    required String decision, // 'approve' | 'reject'
    String? comment,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Check if user already voted
      final hasVoted = await hasUserVoted(familyId, currentUser.uid);
      if (hasVoted) {
        return false; // User already voted
      }

      // Get reviewer name
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final userName = userDoc.data()?['name'] ?? 'Unknown Admin';

      // Create review document
      final review = FamilyReview(
        id: '', // Will be set by Firestore
        familyId: familyId,
        reviewerId: currentUser.uid,
        reviewerName: userName,
        decision: decision,
        comment: comment,
        createdAt: DateTime.now(),
      );

      // Add to family_reviews collection
      await _firestore.collection('family_reviews').add(review.toFirestore());

      // Update family vote counts and safely check quorum inside the transaction
      final familyRef = _firestore.collection('families').doc(familyId);
      final bool justReachedQuorum = await _firestore.runTransaction((
        transaction,
      ) async {
        final familyDoc = await transaction.get(familyRef);
        if (!familyDoc.exists) throw Exception('Family not found');

        final currentReviewerIds = List<String>.from(
          familyDoc.data()?['reviewerIds'] ?? [],
        );
        final currentApproveCount =
            (familyDoc.data()?['approveCount'] ?? 0) as int;
        final currentRejectCount =
            (familyDoc.data()?['rejectCount'] ?? 0) as int;
        final quorumThreshold =
            (familyDoc.data()?['quorumThreshold'] ?? 3) as int;
        final alreadyReached =
            (familyDoc.data()?['quorumReached'] ?? false) as bool;

        // Add reviewer to list
        currentReviewerIds.add(currentUser.uid);

        // Update counts
        final newApproveCount = decision == 'approve'
            ? currentApproveCount + 1
            : currentApproveCount;
        final newRejectCount = decision == 'reject'
            ? currentRejectCount + 1
            : currentRejectCount;

        // Determine if this exact vote crossed the threshold atomically
        final bool isNowReached =
            (newApproveCount >= quorumThreshold) ||
            (newRejectCount >= quorumThreshold);
        final bool triggerQuorumEvent = !alreadyReached && isNowReached;

        transaction.update(familyRef, {
          'reviewerIds': currentReviewerIds,
          'approveCount': newApproveCount,
          'rejectCount': newRejectCount,
          if (triggerQuorumEvent) 'quorumReached': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return triggerQuorumEvent;
      });

      // Log abstract vote audit trail
      await AuditService.logAction(
        action: 'family_review_vote',
        entityType: 'family',
        entityId: familyId,
        details:
            '$userName voted ${decision == 'approve' ? 'to approve' : 'to reject'}',
        metadata: {
          'decision': decision,
          'comment': comment,
          'reviewerId': currentUser.uid,
          'reviewerName': userName,
        },
      );

      // If this specific transaction pushed the family over the edge, run strict workflows
      if (justReachedQuorum) {
        // Send notification to Final Approvers (Admins)
        final familyDoc = await familyRef.get();
        final approveCount = familyDoc.data()?['approveCount'] ?? 0;
        final rejectCount = familyDoc.data()?['rejectCount'] ?? 0;
        final quorumThreshold = familyDoc.data()?['quorumThreshold'] ?? 3;

        await NotificationService.notifyQuorumReached(
          familyId,
          approveCount + rejectCount,
        );

        // Log Quorum audit
        await AuditService.logAction(
          action: 'quorum_reached',
          entityType: 'family',
          entityId: familyId,
          details:
              'Quorum reached with $approveCount approvals and $rejectCount rejections',
          metadata: {
            'approveCount': approveCount,
            'rejectCount': rejectCount,
            'quorumThreshold': quorumThreshold,
          },
        );
      }

      return true;
    } catch (e) {
      print('Error submitting vote: $e');
      rethrow;
    }
  }

  /// Get all reviews for a specific family
  static Future<List<FamilyReview>> getFamilyReviews(String familyId) async {
    try {
      final snapshot = await _firestore
          .collection('family_reviews')
          .where('familyId', isEqualTo: familyId)
          .orderBy('createdAt', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => FamilyReview.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error getting family reviews: $e');
      return [];
    }
  }

  /// Check if a user has already voted on a family
  static Future<bool> hasUserVoted(String familyId, String userId) async {
    try {
      final snapshot = await _firestore
          .collection('family_reviews')
          .where('familyId', isEqualTo: familyId)
          .where('reviewerId', isEqualTo: userId)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking if user voted: $e');
      return false;
    }
  }

  /// Stream of families pending review
  static Stream<QuerySnapshot> getPendingFamiliesStream() {
    return _firestore
        .collection('families')
        .where('status', isEqualTo: 'pending_review')
        .snapshots();
  }

  /// Get count of families pending review
  static Future<int> getPendingReviewCount() async {
    try {
      final snapshot = await _firestore
          .collection('families')
          .where('status', isEqualTo: 'pending_review')
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      print('Error getting pending review count: $e');
      return 0;
    }
  }
}
