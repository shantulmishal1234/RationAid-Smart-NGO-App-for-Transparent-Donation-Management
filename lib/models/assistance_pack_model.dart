import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for assistance pack items
class PackItem {
  final String name;
  final String quantity;
  final double estimatedCost;

  PackItem({
    required this.name,
    required this.quantity,
    required this.estimatedCost,
  });

  Map<String, dynamic> toMap() {
    return {'name': name, 'quantity': quantity, 'estimatedCost': estimatedCost};
  }

  factory PackItem.fromMap(Map<String, dynamic> map) {
    return PackItem(
      name: map['name'] ?? '',
      quantity: map['quantity'] ?? '',
      estimatedCost: (map['estimatedCost'] ?? 0).toDouble(),
    );
  }
}

/// Model for assistance packs
class AssistancePack {
  final String id;
  final String name;
  final String packType;
  final String? description;
  final int minMembers;
  final int maxMembers;
  final double budgetAmount;
  final List<PackItem> items;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  AssistancePack({
    required this.id,
    required this.name,
    required this.packType,
    this.description,
    required this.minMembers,
    required this.maxMembers,
    required this.budgetAmount,
    required this.items,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'packType': packType,
      'description': description,
      'minMembers': minMembers,
      'maxMembers': maxMembers,
      'budgetAmount': budgetAmount,
      'items': items.map((item) => item.toMap()).toList(),
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory AssistancePack.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return AssistancePack(
      id: doc.id,
      name: data['name'] ?? '',
      packType: data['packType'] ?? '',
      description: data['description'],
      minMembers: data['minMembers'] ?? 1,
      maxMembers: data['maxMembers'] ?? 1,
      budgetAmount: (data['budgetAmount'] ?? 0).toDouble(),
      items:
          (data['items'] as List<dynamic>?)
              ?.map((item) => PackItem.fromMap(item as Map<String, dynamic>))
              .toList() ??
          [],
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  AssistancePack copyWith({
    String? id,
    String? name,
    String? packType,
    String? description,
    int? minMembers,
    int? maxMembers,
    double? budgetAmount,
    List<PackItem>? items,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AssistancePack(
      id: id ?? this.id,
      name: name ?? this.name,
      packType: packType ?? this.packType,
      description: description ?? this.description,
      minMembers: minMembers ?? this.minMembers,
      maxMembers: maxMembers ?? this.maxMembers,
      budgetAmount: budgetAmount ?? this.budgetAmount,
      items: items ?? this.items,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
