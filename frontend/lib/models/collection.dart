import 'enums.dart';

class Collection {
  final String id;
  final String projectId;
  final CollectionType type;
  final String name;
  final int? targetAmount;
  final CollectionStatus status;
  final DateTime? date;
  final DateTime createdAt;

  Collection({
    required this.id,
    required this.projectId,
    required this.type,
    required this.name,
    required this.targetAmount,
    required this.status,
    required this.date,
    required this.createdAt,
  });

  bool get isHarambee => type == CollectionType.harambee;
  bool get isClosed => status == CollectionStatus.closed;

  factory Collection.fromJson(Map<String, dynamic> json) {
    return Collection(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      type: collectionTypeFromJson(json['type'] as String),
      name: json['name'] as String,
      targetAmount: json['target_amount'] as int?,
      status: collectionStatusFromJson(json['status'] as String),
      date: json['date'] == null ? null : DateTime.parse(json['date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
