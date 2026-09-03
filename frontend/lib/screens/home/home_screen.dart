import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/project_summary.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';
import '../project/create_project_screen.dart';
import '../project/project_dashboard_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiService api;

  const HomeScreen({super.key, required this.api});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _dataKey = GlobalKey<AsyncDataViewState<List<ProjectSummary>>>();

  Future<List<ProjectSummary>> _load() async {
    final projects = await widget.api.listProjects();
    // Newest first.
    projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Future.wait(projects.map((p) => loadProjectSummary(widget.api, p)));
  }

  Future<void> _createProject() async {
    // CreateProjectScreen navigates straight to the new project's
    // dashboard via pushReplacement (so the user doesn't land back on an
    // empty form) -- which means this push's own result never resolves
    // to a useful value; it only completes once the user backs all the
    // way out of that dashboard (and everything under it). Reload
    // unconditionally rather than gating on a return value that can't
    // reliably signal "a project was created" here.
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreateProjectScreen(api: widget.api)),
    );
    _dataKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ChangaSmart'),
        titleSpacing: 20,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                'Your contribution collections',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _createProject,
                  icon: const Icon(Icons.add),
                  label: const Text('New Project'),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: AsyncDataView<List<ProjectSummary>>(
                  key: _dataKey,
                  loader: _load,
                  errorHint: 'Make sure the backend is running and API_BASE_URL is correct.',
                  builder: (context, summaries, refresh) {
                    if (summaries.isEmpty) {
                      return EmptyState(
                        icon: Icons.volunteer_activism_outlined,
                        title: 'No projects yet',
                        subtitle: 'Create your first contribution project to get started.',
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async => refresh(),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: summaries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final summary = summaries[index];
                          return _ProjectCard(
                            summary: summary,
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ProjectDashboardScreen(
                                    api: widget.api,
                                    project: summary.project,
                                  ),
                                ),
                              );
                              refresh();
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final ProjectSummary summary;
  final VoidCallback onTap;

  const _ProjectCard({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = summary.project;

    return Card(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      project.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (summary.pendingReviewCount > 0) ...[
                    Icon(Icons.error_outline, size: 16, color: theme.colorScheme.tertiary),
                    const SizedBox(width: 4),
                    Text(
                      '${summary.pendingReviewCount}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.tertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${summary.collections.length} collection${summary.collections.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatKsh(summary.raised),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text('raised', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (summary.target != null)
                    Text(
                      formatPercent(summary.progress),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              if (summary.target != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: summary.progress,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'of ${formatKsh(summary.target!)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
