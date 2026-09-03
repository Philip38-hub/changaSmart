import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/project_summary.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';
import '../../widgets/progress_summary.dart';
import '../../widgets/status_badge.dart';
import '../collection/collection_screen.dart';
import '../collection/create_collection_screen.dart';

class ProjectDashboardScreen extends StatefulWidget {
  final ApiService api;
  final Project project;

  const ProjectDashboardScreen({super.key, required this.api, required this.project});

  @override
  State<ProjectDashboardScreen> createState() => _ProjectDashboardScreenState();
}

class _ProjectDashboardScreenState extends State<ProjectDashboardScreen> {
  final _dataKey = GlobalKey<AsyncDataViewState<ProjectSummary>>();

  Future<ProjectSummary> _load() => loadProjectSummary(widget.api, widget.project);

  bool _hasMainCollection(ProjectSummary summary) =>
      summary.collections.any((e) => e.collection.type == CollectionType.main);

  Future<void> _addCollection(ProjectSummary summary) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateCollectionScreen(
          api: widget.api,
          projectId: widget.project.id,
          suggestMain: !_hasMainCollection(summary),
        ),
      ),
    );
    if (created == true) _dataKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.project.name)),
      body: SafeArea(
        child: AsyncDataView<ProjectSummary>(
          key: _dataKey,
          loader: _load,
          builder: (context, summary, refresh) {
            return RefreshIndicator(
              onRefresh: () async => refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  ProgressSummary(
                    raised: summary.raised,
                    target: summary.target,
                    remaining: summary.target == null ? null : summary.remaining,
                    progress: summary.progress,
                  ),
                  const SizedBox(height: 20),
                  _StatusRow(summary: summary),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Collections', style: Theme.of(context).textTheme.titleMedium),
                      TextButton.icon(
                        onPressed: () => _addCollection(summary),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(_hasMainCollection(summary) ? 'Add Harambee' : 'Add Collection'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (summary.collections.isEmpty)
                    EmptyState(
                      icon: Icons.folder_open,
                      title: 'No collections yet',
                      subtitle: 'Add a Main Contribution to start tracking payments.',
                      action: FilledButton.icon(
                        onPressed: () => _addCollection(summary),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Main Contribution'),
                      ),
                    )
                  else
                    ...summary.collections.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CollectionTile(
                          entry: entry,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CollectionScreen(
                                  api: widget.api,
                                  collectionId: entry.collection.id,
                                ),
                              ),
                            );
                            refresh();
                          },
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final ProjectSummary summary;

  const _StatusRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          _StatusStat(
            icon: Icons.check_circle,
            color: AppColors.confirmed,
            count: summary.confirmedContributorCount,
            label: 'confirmed',
          ),
          _StatusStat(
            icon: Icons.schedule,
            color: AppColors.pending,
            count: summary.pendingContributorCount,
            label: 'pending',
          ),
          _StatusStat(
            icon: Icons.error_outline,
            color: AppColors.needsReview,
            count: summary.pendingReviewCount,
            label: 'need review',
          ),
        ],
      ),
    );
  }
}

class _StatusStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;

  const _StatusStat({
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text('$count', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  final CollectionSummaryEntry entry;
  final VoidCallback onTap;

  const _CollectionTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collection = entry.collection;
    final report = entry.report;
    final isHarambee = collection.type == CollectionType.harambee;

    return Card(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (isHarambee ? AppColors.harambeeAccent : theme.colorScheme.primary)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isHarambee ? Icons.local_fire_department : Icons.account_balance_wallet,
                  color: isHarambee ? AppColors.harambeeAccent : theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(collection.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(formatKsh(report.totalReceived), style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              if (isHarambee) StatusBadge.collectionStatus(collection.status),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
