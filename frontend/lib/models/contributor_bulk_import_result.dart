import 'contributor.dart';

class ContributorBulkImportResult {
  final List<Contributor> created;
  final List<String> skippedNames;

  ContributorBulkImportResult({required this.created, required this.skippedNames});

  factory ContributorBulkImportResult.fromJson(Map<String, dynamic> json) {
    return ContributorBulkImportResult(
      created: (json['created'] as List)
          .map((e) => Contributor.fromJson(e as Map<String, dynamic>))
          .toList(),
      skippedNames: (json['skipped_names'] as List).map((e) => e as String).toList(),
    );
  }
}
