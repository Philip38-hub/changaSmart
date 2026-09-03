import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';
import '../../widgets/status_badge.dart';

class ReportScreen extends StatefulWidget {
  final ApiService api;
  final String collectionId;
  final CollectionType collectionType;

  const ReportScreen({
    super.key,
    required this.api,
    required this.collectionId,
    required this.collectionType,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  Future<CollectionReport> _load() => widget.api.getReport(widget.collectionId);

  @override
  Widget build(BuildContext context) {
    final isHarambee = widget.collectionType == CollectionType.harambee;
    return Scaffold(
      appBar: AppBar(title: const Text('Contribution Summary')),
      body: SafeArea(
        child: AsyncDataView<CollectionReport>(
          loader: _load,
          builder: (context, report, refresh) {
            return RefreshIndicator(
              onRefresh: () async => refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  if (isHarambee)
                    _HarambeeSummary(report: report)
                  else
                    _MainSummary(report: report),
                  const SizedBox(height: 28),
                  Text('Contributor breakdown', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  ...report.contributorBreakdown.map(
                    (entry) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: ListTile(
                        title: Text(entry.name),
                        subtitle: entry.expectedAmount != null
                            ? Text('Expected ${formatKsh(entry.expectedAmount!)}')
                            : null,
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatKsh(entry.totalPaid), style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            StatusBadge.contributorPaid(entry.hasPaid),
                          ],
                        ),
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

class _MainSummary extends StatelessWidget {
  final CollectionReport report;
  const _MainSummary({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(report.name, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(formatKsh(report.totalReceived), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text('Total received', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        Row(
          children: [
            _StatBlock(value: '${report.confirmedContributorCount}', label: 'Confirmed contributors'),
            _StatBlock(value: '${report.pendingContributorCount}', label: 'Pending'),
            _StatBlock(value: '${report.pendingReviewCount}', label: 'Needs review'),
          ],
        ),
        if (report.targetAmount != null) ...[
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Target', style: theme.textTheme.bodySmall),
                  Text(formatKsh(report.targetAmount!), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Remaining', style: theme.textTheme.bodySmall),
                  Text(formatKsh(report.remainingAmount ?? 0), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HarambeeSummary extends StatelessWidget {
  final CollectionReport report;
  const _HarambeeSummary({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.harambeeAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.harambeeAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.local_fire_department, color: AppColors.harambeeAccent),
              SizedBox(width: 8),
              Text('Harambee Summary', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          _KeyValueRow(label: 'Target', value: report.targetAmount != null ? formatKsh(report.targetAmount!) : '—'),
          const SizedBox(height: 8),
          _KeyValueRow(label: 'Raised', value: formatKsh(report.totalReceived)),
          const SizedBox(height: 8),
          _KeyValueRow(label: 'Remaining', value: formatKsh(report.remainingAmount ?? 0)),
          const SizedBox(height: 16),
          Text(
            '${formatPercent(report.progress)} complete',
            style: theme.textTheme.titleMedium?.copyWith(color: AppColors.harambeeAccent, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  const _KeyValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String value;
  final String label;
  const _StatBlock({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
