import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of the procurement request
enum ProcurementStatus {
  pending, // Generated, waiting for purchaser
  purchased, // Receipt uploaded, waiting for admin
  verified, // Admin approved, stock added
  rejected, // Admin rejected receipt
  stocked, // Officially in inventory (reserved)
  delivered, // Handed over to family
  issue_reported, // Purchaser reported an issue
  written_off, // Admin wrote off stock
}

/// Item to be purchased (snapshot from PackItem)
class ProcurementItem {
  final String name;
  final String quantity; // e.g., "10kg"
  final double estimatedCost;
  final double actualCost;
  final bool isPurchased;

  ProcurementItem({
    required this.name,
    required this.quantity,
    required this.estimatedCost,
    this.actualCost = 0.0,
    this.isPurchased = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'estimatedCost': estimatedCost,
      'actualCost': actualCost,
      'isPurchased': isPurchased,
    };
  }

  factory ProcurementItem.fromMap(Map<String, dynamic> map) {
    return ProcurementItem(
      name: map['name'] ?? '',
      quantity: map['quantity'] ?? '',
      estimatedCost: (map['estimatedCost'] ?? 0).toDouble(),
      actualCost: (map['actualCost'] ?? 0).toDouble(),
      isPurchased: map['isPurchased'] ?? false,
    );
  }

  ProcurementItem copyWith({
    String? name,
    String? quantity,
    double? estimatedCost,
    double? actualCost,
    bool? isPurchased,
  }) {
    return ProcurementItem(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      actualCost: actualCost ?? this.actualCost,
      isPurchased: isPurchased ?? this.isPurchased,
    );
  }
}

class ProcurementRequest {
  final String id;
  final String familyId;
  final String familyAddress; // Masked/Area only
  final String packId;
  final String packName;
  final List<ProcurementItem> items;
  final double budgetLimit;
  final double totalSpent;
  final ProcurementStatus status;
  final String? purchaserId;
  final String? purchaserName;
  final DateTime createdAt;
  final DateTime? purchasedAt;
  final DateTime? verifiedAt;
  final String? receiptUrl;
  final String? adminRemarks;
  final String? issueType;
  final String? issueReason;
  final DateTime? issueReportedAt;
  final String? issueReportedBy;
  final DateTime? resolvedAt;
  final String? resolutionAction; // 'write_off', 'ignore'
  final String? resolutionNote;
  final String? reviewStatus;

  ProcurementRequest({
    required this.id,
    required this.familyId,
    required this.familyAddress,
    required this.packId,
    required this.packName,
    required this.items,
    required this.budgetLimit,
    this.totalSpent = 0.0,
    this.status = ProcurementStatus.pending,
    this.purchaserId,
    this.purchaserName,
    required this.createdAt,
    this.purchasedAt,
    this.verifiedAt,
    this.receiptUrl,
    this.adminRemarks,
    this.issueType,
    this.issueReason,
    this.issueReportedAt,
    this.issueReportedBy,
    this.resolvedAt,
    this.resolutionAction,
    this.resolutionNote,
    this.reviewStatus,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'familyId': familyId,
      'familyAddress': familyAddress,
      'packId': packId,
      'packName': packName,
      'items': items.map((e) => e.toMap()).toList(),
      'budgetLimit': budgetLimit,
      'totalSpent': totalSpent,
      'status': status.toString().split('.').last,
      'purchaserId': purchaserId,
      'purchaserName': purchaserName,
      'createdAt': Timestamp.fromDate(createdAt),
      'purchasedAt': purchasedAt != null
          ? Timestamp.fromDate(purchasedAt!)
          : null,
      'verifiedAt': verifiedAt != null ? Timestamp.fromDate(verifiedAt!) : null,
      'receiptUrl': receiptUrl,
      'adminRemarks': adminRemarks,
    };
  }

  factory ProcurementRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return ProcurementRequest(
      id: doc.id,
      familyId: data['familyId'] ?? '',
      familyAddress: data['familyAddress'] ?? '',
      packId: data['packId'] ?? '',
      packName: data['packName'] ?? '',
      items:
          (data['items'] as List<dynamic>?)
              ?.map((e) => ProcurementItem.fromMap(e))
              .toList() ??
          [],
      budgetLimit: (data['budgetLimit'] ?? 0).toDouble(),
      totalSpent: (data['totalSpent'] ?? 0).toDouble(),
      status: ProcurementStatus.values.firstWhere(
        (e) => e.toString().split('.').last == (data['status'] ?? 'pending'),
        orElse: () => ProcurementStatus.pending,
      ),
      purchaserId: data['purchaserId'],
      purchaserName: data['purchaserName'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      purchasedAt: (data['purchasedAt'] as Timestamp?)?.toDate(),
      verifiedAt: (data['verifiedAt'] as Timestamp?)?.toDate(),
      receiptUrl: data['receiptUrl'],
      adminRemarks: data['adminRemarks'],
      issueType: data['issueType'],
      issueReason: data['issueReason'],
      issueReportedAt: (data['issueReportedAt'] as Timestamp?)?.toDate(),
      issueReportedBy: data['issueReportedBy'],
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      resolutionAction: data['resolutionAction'],
      resolutionNote: data['resolutionNote'],
      reviewStatus: data['reviewStatus'],
    );
  }
}
