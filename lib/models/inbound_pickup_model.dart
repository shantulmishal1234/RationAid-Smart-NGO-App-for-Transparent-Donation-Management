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

  /// True if this is a GRF Pool pickup — items go into the GRF warehouse,
  /// not a specific family's stock. Admin assigns them after collection.
  final bool isGrfPool;

  /// True if this pickup was created from a Smart In-Kind split waterfall.
  /// Used by _markCollected to apply inKindValue directly to the family.
  final bool isSmartSplit;

  /// Items to collect. { "Rice": 10, "Flour": 20 }
  final Map<String, num> items;

  /// Item units at submission. { "Rice": "kg", "Flour": "kg" }
  final Map<String, String>? itemUnits;

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
    this.isGrfPool = false,
    this.isSmartSplit = false,
    this.itemUnits,
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
      isGrfPool:
          data['isGrfPool'] as bool? ??
          (data['familyId'] == 'general_relief_fund'),
      isSmartSplit: data['isSmartSplit'] as bool? ?? false,
      items: Map<String, num>.from(
        (data['items'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (num.tryParse(v.toString()) ?? 0)),
        ),
      ),
      itemUnits: data['itemUnits'] != null
          ? Map<String, String>.from(data['itemUnits'] as Map)
          : null,
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
      'isGrfPool': isGrfPool,
      'isSmartSplit': isSmartSplit,
      'items': items,
      'itemUnits': itemUnits,
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
    Map<String, String>? itemUnits,
    bool? isGrfPool,
    bool? isSmartSplit,
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
      isGrfPool: isGrfPool ?? this.isGrfPool,
      isSmartSplit: isSmartSplit ?? this.isSmartSplit,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      pickupProofUrl: pickupProofUrl ?? this.pickupProofUrl,
      proofUploadedAt: proofUploadedAt ?? this.proofUploadedAt,
      note: note ?? this.note,
      itemUnits: itemUnits ?? this.itemUnits,
    );
  }
}
