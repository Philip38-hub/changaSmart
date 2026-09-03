import 'enums.dart';

class Project {
  final String id;
  final String name;
  final int? targetAmount;
  final ProjectStatus status;
  final DateTime createdAt;

  Project({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.status,
    required this.createdAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      targetAmount: json['target_amount'] as int?,
      status: projectStatusFromJson(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
