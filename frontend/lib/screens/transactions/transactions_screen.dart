import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';
import '../../widgets/status_badge.dart';

class TransactionsScreen extends StatefulWidget {
  final ApiService api;
  final String collectionId;

  /// Set when this screen was opened from a real-time SMS alert (see
  /// SmsAlertService) after a fully unattended auto-import -- scrolls to
  /// and visually highlights that transaction once the list loads.
  final String? highlightTransactionId;

  const TransactionsScreen({
    super.key,
    required this.api,
    required this.collectionId,
    this.highlightTransactionId,
  });

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _dataKey = GlobalKey<AsyncDataViewState<_TransactionsData>>();
  final GlobalKey _highlightedTileKey = GlobalKey();
  bool _scrolledToHighlight = false;

  Future<_TransactionsData> _load() async {
    final transactions = await widget.api.listTransactions(widget.collectionId);
    final report = await widget.api.getReport(widget.collectionId);
    final names = {for (final e in report.contributorBreakdown) e.contributorId: e.name};
    transactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _TransactionsData(transactions: transactions, contributorNames: names);
  }

  Future<void> _recordPayment() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecordPaymentSheet(api: widget.api, collectionId: widget.collectionId),
    );
    if (added == true) _dataKey.currentState?.reload();
  }

  void _scheduleHighlightScroll(List<Transaction> transactions) {
    if (_scrolledToHighlight || widget.highlightTransactionId == null) return;
    if (!transactions.any((t) => t.id == widget.highlightTransactionId)) return;
    _scrolledToHighlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final highlightContext = _highlightedTileKey.currentContext;
      if (highlightContext != null) {
        Scrollable.ensureVisible(
          highlightContext,
          duration: const Duration(milliseconds: 300),
          alignment: 0.1,
        );
      }
    });
  }

  Future<void> _undoAutoImport(Transaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Undo automatic import?'),
        content: Text(
          'This will remove ${formatKsh(transaction.amount)} from '
          '${transaction.senderName}\'s recorded contributions.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Undo')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.api.reverseTransaction(transaction.id);
      _dataKey.currentState?.reload();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _recordPayment,
        icon: const Icon(Icons.add),
        label: const Text('Record Payment'),
      ),
      body: SafeArea(
        child: AsyncDataView<_TransactionsData>(
          key: _dataKey,
          loader: _load,
          builder: (context, data, refresh) {
            if (data.transactions.isEmpty) {
              return EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions yet',
                subtitle: 'Record a payment as M-PESA confirmations come in.',
                action: FilledButton.icon(
                  onPressed: _recordPayment,
                  icon: const Icon(Icons.add),
                  label: const Text('Record Payment'),
                ),
              );
            }
            _scheduleHighlightScroll(data.transactions);
            return RefreshIndicator(
              onRefresh: () async => refresh(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: data.transactions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final txn = data.transactions[index];
                  final creditedName = txn.matchedContributorId == null
                      ? null
                      : data.contributorNames[txn.matchedContributorId];
                  final isHighlighted = txn.id == widget.highlightTransactionId;
                  return _TransactionTile(
                    key: isHighlighted ? _highlightedTileKey : null,
                    transaction: txn,
                    creditedName: creditedName,
                    highlighted: isHighlighted,
                    onUndoAutoImport: () => _undoAutoImport(txn),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TransactionsData {
  final List<Transaction> transactions;
  final Map<String, String> contributorNames;
  _TransactionsData({required this.transactions, required this.contributorNames});
}

class _TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final String? creditedName;
  final bool highlighted;
  final VoidCallback onUndoAutoImport;

  const _TransactionTile({
    super.key,
    required this.transaction,
    required this.creditedName,
    this.highlighted = false,
    required this.onUndoAutoImport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canUndo =
        transaction.autoImportedUnattended && transaction.status == TransactionStatus.confirmed;
    return Card(
      color: highlighted ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: highlighted ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    transaction.senderName,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(formatKsh(transaction.amount), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${transaction.mpesaCode} • ${formatDateTime(transaction.timestamp)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (creditedName != null && creditedName != transaction.senderName) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.subdirectory_arrow_right, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'Credited to $creditedName',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                StatusBadge.transaction(transaction.status),
                if (transaction.autoImportedUnattended) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Auto-imported',
                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 11),
                    ),
                  ),
                ],
                const Spacer(),
                if (canUndo)
                  TextButton.icon(
                    onPressed: onUndoAutoImport,
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Undo'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger, padding: EdgeInsets.zero),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordPaymentSheet extends StatefulWidget {
  final ApiService api;
  final String collectionId;

  const _RecordPaymentSheet({required this.api, required this.collectionId});

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _senderController = TextEditingController();
  final _amountController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    _senderController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await widget.api.createTransaction(
        collectionId: widget.collectionId,
        mpesaCode: _codeController.text.trim(),
        senderName: _senderController.text.trim(),
        amount: int.parse(_amountController.text.trim().replaceAll(',', '')),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Record Payment', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Enter the details from an M-PESA confirmation SMS.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'M-PESA code', hintText: 'QAX1AAA111'),
              autofocus: true,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'M-PESA code is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _senderController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Sender name', hintText: 'As shown on the SMS'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Sender name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Amount', prefixText: 'KSh '),
              validator: (v) {
                final parsed = int.tryParse((v ?? '').replaceAll(',', ''));
                if (parsed == null) return 'Enter a whole number';
                if (parsed <= 0) return 'Amount must be greater than zero';
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Record Payment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
