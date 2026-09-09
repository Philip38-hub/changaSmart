import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/async_data_view.dart';
import '../../widgets/review_action_card.dart';

/// Lists every transaction currently NEEDS_REVIEW in this collection --
/// reachable any time from the collection screen, independent of any one
/// reconcile run. Human decisions made here are authoritative and final.
class ReviewScreen extends StatefulWidget {
  final ApiService api;
  final String collectionId;

  const ReviewScreen({super.key, required this.api, required this.collectionId});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _dataKey = GlobalKey<AsyncDataViewState<_ReviewData>>();

  Future<_ReviewData> _load() async {
    final transactions = await widget.api.listTransactions(widget.collectionId);
    final report = await widget.api.getReport(widget.collectionId);
    final needsReview = transactions.where((t) => t.needsReview).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final names = {for (final e in report.contributorBreakdown) e.contributorId: e.name};
    return _ReviewData(transactions: needsReview, contributorNames: names);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: SafeArea(
        child: AsyncDataView<_ReviewData>(
          key: _dataKey,
          loader: _load,
          builder: (context, data, refresh) {
            if (data.transactions.isEmpty) {
              return const EmptyState(
                icon: Icons.task_alt,
                title: 'Nothing needs review',
                subtitle: 'All caught up.',
              );
            }
            return ApiServiceProvider(
              api: widget.api,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    '${data.transactions.length} Contribution${data.transactions.length == 1 ? '' : 's'} '
                    'Need${data.transactions.length == 1 ? 's' : ''} Your Attention',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  ...data.transactions.map(
                    (txn) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ReviewActionCard(
                        collectionId: widget.collectionId,
                        transaction: txn,
                        suggestedContributorName: txn.matchedContributorId == null
                            ? null
                            : data.contributorNames[txn.matchedContributorId],
                        onResolved: (_) => refresh(),
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

class _ReviewData {
  final List<Transaction> transactions;
  final Map<String, String> contributorNames;
  _ReviewData({required this.transactions, required this.contributorNames});
}
