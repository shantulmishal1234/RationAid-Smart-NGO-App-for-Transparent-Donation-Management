import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a Purchaser task to physically collect in-kind items from a donor.
/// Created automatically when Admin verifies an in-kind donation.
class InboundPickup {
  final String id;
  final String batchId; // warehouse_stock document ID
  final String familyId;
  final String donationId;
  final String donorId;
  final String donorName;
  final String contactNumber;
  final String pickupAddress;

  /// Items to collect. { "Rice": 10, "Flour": 20 }
  final Map<String, int> items;

  /// Purchaser UID who accepted the task. Null if still in open pool.
  final String? assignedTo;

  /// open → in_progress → completed | failed
  final String status;

  /// Proof photo uploaded after collection.
  final String? pickupProofUrl;
  final DateTime? proofUploadedAt;

  /// Purchaser's optional note (e.g., "Flour bag was slightly less, ~19kg").
  final String? note;

  final DateTime createdAt;

  const InboundPickup({
    required this.id,
    required this.batchId,
    required this.familyId,
    required this.donationId,
    required this.donorId,
    required this.donorName,
    required this.contactNumber,
    required this.pickupAddress,
    required this.items,
    required this.status,
    required this.createdAt,
    this.assignedTo,
    this.pickupProofUrl,
    this.proofUploadedAt,
    this.note,
  });

  factory InboundPickup.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InboundPickup(
      id: doc.id,
      batchId: data['batchId'] ?? '',
      familyId: data['familyId'] ?? '',
      donationId: data['donationId'] ?? '',
      donorId: data['donorId'] ?? '',
      donorName: data['donorName'] ?? '',
      contactNumber: data['contactNumber'] ?? '',
      pickupAddress: data['pickupAddress'] ?? '',
      items: Map<String, int>.from(
        (data['items'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
      ),
      status: data['status'] ?? 'open',
      assignedTo: data['assignedTo'],
      pickupProofUrl: data['pickupProofUrl'],
      proofUploadedAt: (data['proofUploadedAt'] as Timestamp?)?.toDate(),
      note: data['note'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'batchId': batchId,
      'familyId': familyId,
      'donationId': donationId,
      'donorId': donorId,
      'donorName': donorName,
      'contactNumber': contactNumber,
      'pickupAddress': pickupAddress,
      'items': items,
      'status': status,
      if (assignedTo != null) 'assignedTo': assignedTo,
      if (pickupProofUrl != null) 'pickupProofUrl': pickupProofUrl,
      if (proofUploadedAt != null)
        'proofUploadedAt': Timestamp.fromDate(proofUploadedAt!),
      if (note != null) 'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  InboundPickup copyWith({
    String? status,
    String? assignedTo,
    String? pickupProofUrl,
    DateTime? proofUploadedAt,
    String? note,
  }) {
    return InboundPickup(
      id: id,
      batchId: batchId,
      familyId: familyId,
      donationId: donationId,
      donorId: donorId,
      donorName: donorName,
      contactNumber: contactNumber,
      pickupAddress: pickupAddress,
      items: items,
      createdAt: createdAt,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      pickupProofUrl: pickupProofUrl ?? this.pickupProofUrl,
      proofUploadedAt: proofUploadedAt ?? this.proofUploadedAt,
      note: note ?? this.note,
    );
  }
}
