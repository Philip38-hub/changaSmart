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
  final String collectionId;
  final Transaction transaction;
  final String? suggestedContributorName;
  final void Function(Transaction updated) onResolved;

  const ReviewActionCard({
    super.key,
    required this.collectionId,
    required this.transaction,
    required this.suggestedContributorName,
    required this.onResolved,
  });

  @override
  State<ReviewActionCard> createState() => _ReviewActionCardState();
}

class _ReviewActionCardState extends State<ReviewActionCard> {
  bool _busy = false;
  DateTime? _overrideDate;

  Future<void> _resolve(
    BuildContext context,
    ApiService api,
    HumanReviewAction action, {
    String? contributorIdOverride,
  }) async {
    setState(() => _busy = true);
    try {
      final updated = await api.resolveReview(
        transactionId: widget.transaction.id,
        action: action,
        contributorId: contributorIdOverride ??
            (action == HumanReviewAction.creditSuggestedContributor
                ? widget.transaction.matchedContributorId
                : null),
        effectiveDate: _overrideDate,
      );
      widget.onResolved(updated);
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickContributor(
    BuildContext context,
    ApiService api, {
    required HumanReviewAction action,
    required String sheetTitle,
  }) async {
    List<Contributor> contributors;
    try {
      contributors = await api.listContributors(widget.collectionId);
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, e);
      return;
    }
    if (!context.mounted) return;

    final chosen = await showModalBottomSheet<Contributor>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ContributorPickerSheet(contributors: contributors, title: sheetTitle),
    );
    if (chosen == null) return;
    if (!context.mounted) return;
    await _resolve(context, api, action, contributorIdOverride: chosen.id);
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _overrideDate ?? widget.transaction.timestamp,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: 'Which date should this count toward?',
    );
    if (picked != null) setState(() => _overrideDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiServiceProvider.of(context);
    final theme = Theme.of(context);
    final txn = widget.transaction;
    final hasSuggestion = txn.matchedContributorId != null && widget.suggestedContributorName != null;
    final effectiveDate = _overrideDate ?? txn.timestamp;

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
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 15, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Record for: ${formatDate(effectiveDate)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _pickDate(context),
                  child: const Text('Change'),
                ),
                if (_overrideDate != null)
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _overrideDate = null),
                    child: const Text('Reset'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
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
                    child: OutlinedButton.icon(
                      onPressed: () => _pickContributor(
                        context,
                        api,
                        action: HumanReviewAction.creditSuggestedContributor,
                        sheetTitle: 'Choose a contributor',
                      ),
                      icon: const Icon(Icons.person_search_outlined, size: 18),
                      label: const Text('Choose a different contributor'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _pickContributor(
                        context,
                        api,
                        action: HumanReviewAction.ignore,
                        sheetTitle: 'Who is this? (already recorded, won\'t be counted again)',
                      ),
                      icon: const Icon(Icons.link_outlined, size: 18),
                      label: const Text('Already recorded -- just remember this name'),
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

class _ContributorPickerSheet extends StatefulWidget {
  final List<Contributor> contributors;
  final String title;
  const _ContributorPickerSheet({required this.contributors, required this.title});

  @override
  State<_ContributorPickerSheet> createState() => _ContributorPickerSheetState();
}

class _ContributorPickerSheetState extends State<_ContributorPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.contributors
        .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search contributors',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No contributors match'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final c = filtered[index];
                        return ListTile(
                          title: Text(c.name),
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
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
