import '../models/models.dart';
import 'api_service.dart';

/// Aggregates a project's collections into the "target / raised / status"
/// summary the home screen and project dashboard show. The backend has no
/// single endpoint for this (a project's own target_amount is optional and
/// collection-level totals are what's authoritative), so this composes
/// existing endpoints -- GET .../collections then GET .../report per
/// collection -- rather than adding aggregation logic to the backend for
/// what is purely a display concern.
class CollectionSummaryEntry {
  final Collection collection;
  final CollectionReport report;

  CollectionSummaryEntry({required this.collection, required this.report});
}

class ProjectSummary {
  final Project project;
  final List<CollectionSummaryEntry> collections;

  ProjectSummary({required this.project, required this.collections});

  int get raised => collections.fold(0, (sum, e) => sum + e.report.totalReceived);

  int? get target {
    if (project.targetAmount != null) return project.targetAmount;
    if (collections.isEmpty) return null;
    final sum = collections.fold<int>(0, (s, e) => s + (e.report.targetAmount ?? 0));
    return sum == 0 ? null : sum;
  }

  int get remaining {
    final t = target;
    if (t == null) return 0;
    return (t - raised).clamp(0, t);
  }

  double get progress {
    final t = target;
    if (t == null || t == 0) return 0;
    return (raised / t).clamp(0.0, 1.0);
  }

  int get confirmedContributorCount =>
      collections.fold(0, (sum, e) => sum + e.report.confirmedContributorCount);

  int get pendingReviewCount =>
      collections.fold(0, (sum, e) => sum + e.report.pendingReviewCount);

  int get pendingContributorCount =>
      collections.fold(0, (sum, e) => sum + e.report.pendingContributorCount);
}

Future<ProjectSummary> loadProjectSummary(ApiService api, Project project) async {
  final collections = await api.listCollections(project.id);
  final entries = await Future.wait(collections.map((collection) async {
    final report = await api.getReport(collection.id);
    return CollectionSummaryEntry(collection: collection, report: report);
  }));
  return ProjectSummary(project: project, collections: entries);
}
