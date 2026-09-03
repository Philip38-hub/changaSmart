import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'async_data_view.dart';

/// The core review interaction: a transaction the deterministic layer and
/// the agent could not confidently match gets shown with full context --
/// who actually paid, who the system *thinks* it might be for, and why --
/// and the human makes the final, authoritative call. Never pre-selects an
/// answer; crediting the suggested contributor is a deliberate tap, never
/// automatic just because the amount lines up.
class ReviewActionCard extends StatefulWidget {
  final Transaction transaction;
  final String? suggestedContributorName;
  final void Function(Transaction updated) onResolved;

  const ReviewActionCard({
    super.key,
    required this.transaction,
    required this.suggestedContributorName,
    required this.onResolved,
  });

  @override
  State<ReviewActionCard> createState() => _ReviewActionCardState();
}

class _ReviewActionCardState extends State<ReviewActionCard> {
  bool _busy = false;

  Future<void> _resolve(BuildContext context, ApiService api, HumanReviewAction action) async {
    setState(() => _busy = true);
    try {
      final updated = await api.resolveReview(
        transactionId: widget.transaction.id,
        action: action,
        contributorId: action == HumanReviewAction.creditSuggestedContributor
            ? widget.transaction.matchedContributorId
            : null,
      );
      widget.onResolved(updated);
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiServiceProvider.of(context);
    final theme = Theme.of(context);
    final txn = widget.transaction;
    final hasSuggestion = txn.matchedContributorId != null && widget.suggestedContributorName != null;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.needsReview.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.needsReview, size: 20),
                const SizedBox(width: 8),
                Text(
                  formatKsh(txn.amount),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(txn.mpesaCode, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            _Field(label: 'Paid by', value: txn.senderName),
            if (hasSuggestion) ...[
              const SizedBox(height: 8),
              _Field(label: 'Possible contributor', value: widget.suggestedContributorName!),
            ],
            if (txn.reviewReason != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  txn.reviewReason!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_busy)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
            else
              Column(
                children: [
                  if (hasSuggestion)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _resolve(context, api, HumanReviewAction.creditSuggestedContributor),
                        child: Text('Credit ${widget.suggestedContributorName}'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _resolve(context, api, HumanReviewAction.creditSenderAsContributor),
                      child: Text('Credit ${txn.senderName}'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => _resolve(context, api, HumanReviewAction.ignore),
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      child: const Text('Ignore'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;

  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// Small InheritedWidget so ReviewActionCard (a reusable widget dropped
/// into two different screens) doesn't need ApiService threaded through
/// every constructor by hand.
class ApiServiceProvider extends InheritedWidget {
  final ApiService api;

  const ApiServiceProvider({super.key, required this.api, required super.child});

  static ApiService of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<ApiServiceProvider>();
    assert(provider != null, 'ApiServiceProvider not found in context');
    return provider!.api;
  }

  @override
  bool updateShouldNotify(ApiServiceProvider oldWidget) => oldWidget.api != api;
}
