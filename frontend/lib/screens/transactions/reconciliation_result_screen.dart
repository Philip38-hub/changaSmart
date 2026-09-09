import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';
import '../../widgets/review_action_card.dart';

class ReconciliationResultScreen extends StatefulWidget {
  final ApiService api;
  final String collectionId;
  final List<ReconciliationDecision> decisions;

  const ReconciliationResultScreen({
    super.key,
    required this.api,
    required this.collectionId,
    required this.decisions,
  });

  @override
  State<ReconciliationResultScreen> createState() => _ReconciliationResultScreenState();
}

class _ReconciliationResultScreenState extends State<ReconciliationResultScreen> {
  final _dataKey = GlobalKey<AsyncDataViewState<_ResultData>>();
  final Set<String> _resolvedIds = {};

  Future<_ResultData> _load() async {
    final transactions = await widget.api.listTransactions(widget.collectionId);
    final report = await widget.api.getReport(widget.collectionId);
    final txById = {for (final t in transactions) t.id: t};
    final names = {for (final e in report.contributorBreakdown) e.contributorId: e.name};
    return _ResultData(transactionsById: txById, contributorNames: names);
  }

  @override
  Widget build(BuildContext context) {
    final autoMatched = widget.decisions.where((d) => d.isAutoMatched).toList();
    final needsReview = widget.decisions.where((d) => d.needsReview).toList();
    final errors = widget.decisions.where((d) => d.isError).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Reconciliation Result')),
      body: SafeArea(
        child: AsyncDataView<_ResultData>(
          key: _dataKey,
          loader: _load,
          builder: (context, data, refresh) {
            return ApiServiceProvider(
              api: widget.api,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (autoMatched.isNotEmpty) ...[
                    Text('✓ Automatically matched', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    ...autoMatched.map((d) {
                      final txn = data.transactionsById[d.transactionId];
                      return _AutoMatchedCard(
                        api: widget.api,
                        collectionId: widget.collectionId,
                        decision: d,
                        transaction: txn,
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                  if (needsReview.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.needsReview, size: 20),
                        const SizedBox(width: 8),
                        Text('Needs your confirmation', style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...needsReview.where((d) => !_resolvedIds.contains(d.transactionId)).map((d) {
                      final txn = data.transactionsById[d.transactionId];
                      if (txn == null) return const SizedBox.shrink();
                      final suggestedName = txn.matchedContributorId == null
                          ? null
                          : data.contributorNames[txn.matchedContributorId];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ReviewActionCard(
                          collectionId: widget.collectionId,
                          transaction: txn,
                          suggestedContributorName: suggestedName,
                          onResolved: (_) => setState(() => _resolvedIds.add(d.transactionId)),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                  if (errors.isNotEmpty) ...[
                    Text('⚠ Could not reconcile', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    ...errors.map((d) => _ErrorCard(decision: d)),
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

class _ResultData {
  final Map<String, Transaction> transactionsById;
  final Map<String, String> contributorNames;
  _ResultData({required this.transactionsById, required this.contributorNames});
}

class _AutoMatchedCard extends StatefulWidget {
  final ApiService api;
  final String collectionId;
  final ReconciliationDecision decision;
  final Transaction? transaction;

  const _AutoMatchedCard({
    required this.api,
    required this.collectionId,
    required this.decision,
    required this.transaction,
  });

  @override
  State<_AutoMatchedCard> createState() => _AutoMatchedCardState();
}

class _AutoMatchedCardState extends State<_AutoMatchedCard> {
  List<DateTime>? _missingWeeks;
  DateTime? _movedTo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final contributorId = widget.decision.suggestedContributorId;
    if (contributorId == null) return;
    widget.api
        .getMissingWeeks(collectionId: widget.collectionId, contributorId: contributorId)
        .then((weeks) {
      if (mounted) setState(() => _missingWeeks = weeks);
    }).catchError((_) {
      // Best-effort nudge only -- if this fails, just don't show it.
      if (mounted) setState(() => _missingWeeks = const []);
    });
  }

  Future<void> _moveTo(DateTime weekStart) async {
    final txn = widget.transaction;
    if (txn == null) return;
    setState(() => _busy = true);
    try {
      await widget.api.setTransactionEffectiveDate(
        transactionId: txn.id,
        effectiveDate: weekStart,
      );
      if (mounted) setState(() => _movedTo = weekStart);
    } catch (e) {
      if (mounted && context.mounted) showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDifferentWeek(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _missingWeeks?.first ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: 'Which week should this count toward?',
    );
    if (picked != null) await _moveTo(picked);
  }

  String _weekRangeLabel(DateTime start) {
    final end = start.add(const Duration(days: 6));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(start.day)}/${two(start.month)} - ${two(end.day)}/${two(end.month)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decision = widget.decision;
    final transaction = widget.transaction;
    final missingWeeks = _missingWeeks;
    final showGapNudge = _movedTo == null && missingWeeks != null && missingWeeks.isNotEmpty;

    return Card(
      color: AppColors.confirmed.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.confirmed.withValues(alpha: 0.3)),
      ),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.confirmed),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        decision.paidBy ?? 'Unknown',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        transaction != null ? formatKsh(transaction.amount) : '',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        decision.reason ?? 'Matched with expected contribution',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_movedTo != null) ...[
              const SizedBox(height: 10),
              Text(
                'Recorded for the week of ${_weekRangeLabel(_movedTo!)}',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.confirmed, fontWeight: FontWeight.w600),
              ),
            ] else if (showGapNudge) ...[
              const Divider(height: 20),
              Text(
                '${decision.paidBy ?? 'This contributor'} is missing the week of '
                '${_weekRangeLabel(missingWeeks.first)}. Recorded so far for the '
                'week of ${transaction != null ? _weekRangeLabel(transaction.timestamp) : '-'}.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (_busy)
                const Center(child: Padding(padding: EdgeInsets.all(4), child: CircularProgressIndicator(strokeWidth: 2)))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => _moveTo(missingWeeks.first),
                      child: Text('Move to week of ${_weekRangeLabel(missingWeeks.first)}'),
                    ),
                    OutlinedButton(
                      onPressed: () => _pickDifferentWeek(context),
                      child: const Text('Choose a different week'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final ReconciliationDecision decision;

  const _ErrorCard({required this.decision});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.danger.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber, color: AppColors.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                decision.error ?? 'This transaction could not be reconciled. It is still pending -- try again shortly.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
