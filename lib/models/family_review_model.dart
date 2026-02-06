import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single admin's vote on a family during the review process
class FamilyReview {
  final String id;
  final String familyId;
  final String reviewerId;
  final String reviewerName;
  final String decision; // 'approve' | 'reject'
  final String? comment;
  final DateTime createdAt;

  FamilyReview({
    required this.id,
    required this.familyId,
    required this.reviewerId,
    required this.reviewerName,
    required this.decision,
    this.comment,
    required this.createdAt,
  });

  /// Factory constructor from Firestore document
  factory FamilyReview.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FamilyReview(
      id: doc.id,
      familyId: data['familyId'] ?? '',
      reviewerId: data['reviewerId'] ?? '',
      reviewerName: data['reviewerName'] ?? 'Unknown',
      decision: data['decision'] ?? '',
      comment: data['comment'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Convert to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'familyId': familyId,
      'reviewerId': reviewerId,
      'reviewerName': reviewerName,
      'decision': decision,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// Check if review is an approval
  bool get isApproval => decision == 'approve';

  /// Check if review is a rejection
  bool get isRejection => decision == 'reject';
}
