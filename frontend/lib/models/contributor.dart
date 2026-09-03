import 'enums.dart';

class Contributor {
  final String id;
  final String collectionId;
  final String name;
  final int? expectedAmount;
  final String? phone;
  final ContributorStatus status;

  Contributor({
    required this.id,
    required this.collectionId,
    required this.name,
    required this.expectedAmount,
    required this.phone,
    required this.status,
  });

  factory Contributor.fromJson(Map<String, dynamic> json) {
    return Contributor(
      id: json['id'] as String,
      collectionId: json['collection_id'] as String,
      name: json['name'] as String,
      expectedAmount: json['expected_amount'] as int?,
      phone: json['phone'] as String?,
      status: contributorStatusFromJson(json['status'] as String),
    );
  }
}
