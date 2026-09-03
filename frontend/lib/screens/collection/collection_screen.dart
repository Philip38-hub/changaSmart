import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';
import '../../widgets/progress_summary.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/whatsapp_sheet.dart';
import '../contributors/contributors_screen.dart';
import '../report/report_screen.dart';
import '../review/review_screen.dart';
import '../transactions/reconciliation_result_screen.dart';
import '../transactions/transactions_screen.dart';

class CollectionScreen extends StatefulWidget {
  final ApiService api;
  final String collectionId;

  const CollectionScreen({super.key, required this.api, required this.collectionId});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _dataKey = GlobalKey<AsyncDataViewState<_CollectionData>>();
  bool _reconciling = false;
  bool _closing = false;

  Future<_CollectionData> _load() async {
    final collection = await widget.api.getCollection(widget.collectionId);
    final report = await widget.api.getReport(widget.collectionId);
    return _CollectionData(collection: collection, report: report);
  }

  void _refresh() => _dataKey.currentState?.reload();

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _refresh();
  }

  Future<void> _reconcile() async {
    setState(() => _reconciling = true);
    try {
      final decisions = await widget.api.reconcile(widget.collectionId);
      if (!mounted) return;
      if (decisions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to reconcile -- no pending transactions.')),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReconciliationResultScreen(
            api: widget.api,
            collectionId: widget.collectionId,
            decisions: decisions,
          ),
        ),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  Future<void> _closeHarambee() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Close Harambee?'),
        content: const Text(
          'This marks the Harambee as closed. You can still view its report and WhatsApp update afterwards.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Close')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _closing = true);
    try {
      await widget.api.closeCollection(widget.collectionId);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  void _showWhatsappSheet(CollectionType type) {
    showWhatsappSheet(context: context, api: widget.api, collectionId: widget.collectionId, type: type);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AsyncDataView<_CollectionData>(
          key: _dataKey,
          loader: _load,
          builder: (context, data, refresh) {
            final collection = data.collection;
            final report = data.report;
            final isHarambee = collection.type == CollectionType.harambee;
            final accent = isHarambee ? AppColors.harambeeAccent : Theme.of(context).colorScheme.primary;

            return RefreshIndicator(
              onRefresh: () async => refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              isHarambee ? Icons.local_fire_department : Icons.account_balance_wallet,
                              color: accent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isHarambee ? 'HARAMBEE' : 'MAIN CONTRIBUTION',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (isHarambee) StatusBadge.collectionStatus(collection.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(collection.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (isHarambee && collection.date != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      formatDate(collection.date!),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ProgressSummary(
                    raised: report.totalReceived,
                    target: report.targetAmount,
                    remaining: report.remainingAmount,
                    progress: report.progress,
                    accentColor: accent,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ChipStat(icon: Icons.check_circle, color: AppColors.confirmed, label: '${report.confirmedContributorCount} confirmed'),
                      _ChipStat(icon: Icons.schedule, color: AppColors.pending, label: '${report.pendingContributorCount} pending'),
                      if (report.pendingReviewCount > 0)
                        _ChipStat(icon: Icons.error_outline, color: AppColors.needsReview, label: '${report.pendingReviewCount} need review'),
                    ],
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _reconciling ? null : _reconcile,
                      icon: _reconciling
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.sync),
                      label: const Text('Reconcile Contributions'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ActionTile(
                    icon: Icons.people_outline,
                    label: 'Contributors',
                    trailing: '${report.contributorBreakdown.length}',
                    onTap: () => _push(ContributorsScreen(api: widget.api, collectionId: widget.collectionId)),
                  ),
                  _ActionTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Transactions',
                    onTap: () => _push(TransactionsScreen(api: widget.api, collectionId: widget.collectionId)),
                  ),
                  if (report.pendingReviewCount > 0)
                    _ActionTile(
                      icon: Icons.error_outline,
                      label: 'Needs your review',
                      trailing: '${report.pendingReviewCount}',
                      highlight: true,
                      onTap: () => _push(ReviewScreen(api: widget.api, collectionId: widget.collectionId)),
                    ),
                  _ActionTile(
                    icon: Icons.bar_chart_outlined,
                    label: 'Report',
                    onTap: () => _push(ReportScreen(api: widget.api, collectionId: widget.collectionId, collectionType: collection.type)),
                  ),
                  _ActionTile(
                    icon: Icons.chat_bubble_outline,
                    label: 'WhatsApp Update',
                    onTap: () => _showWhatsappSheet(collection.type),
                  ),
                  if (isHarambee && !collection.isClosed) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _closing ? null : _closeHarambee,
                        icon: _closing
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.lock_outline),
                        label: const Text('Close Harambee'),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CollectionData {
  final Collection collection;
  final CollectionReport report;
  _CollectionData({required this.collection, required this.report});
}

class _ChipStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _ChipStat({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final bool highlight;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    this.trailing,
    this.highlight = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight ? AppColors.needsReview : theme.colorScheme.onSurface;
    return Card(
      color: highlight ? AppColors.needsReview.withValues(alpha: 0.06) : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: highlight ? AppColors.needsReview.withValues(alpha: 0.3) : theme.colorScheme.outlineVariant),
      ),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null) ...[
              Text(trailing!, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
            ],
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
