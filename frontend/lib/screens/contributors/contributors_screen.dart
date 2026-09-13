import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';
import '../../widgets/status_badge.dart';
import 'import_contributors_screen.dart';

class ContributorsScreen extends StatefulWidget {
  final ApiService api;
  final String collectionId;

  const ContributorsScreen({super.key, required this.api, required this.collectionId});

  @override
  State<ContributorsScreen> createState() => _ContributorsScreenState();
}

class _ContributorsScreenState extends State<ContributorsScreen> {
  final _dataKey = GlobalKey<AsyncDataViewState<CollectionReport>>();

  Future<CollectionReport> _load() => widget.api.getReport(widget.collectionId);

  Future<void> _addContributor() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ContributorFormSheet(api: widget.api, collectionId: widget.collectionId),
    );
    if (added == true) _dataKey.currentState?.reload();
  }

  /// Contributors can be renamed/re-targeted at any point in the
  /// collection's life -- e.g. correcting a nickname, or adding the
  /// group's own collector after the fact once money that never generated
  /// an M-PESA-to-self message is noticed. The breakdown entry the list
  /// renders doesn't carry `phone`, so fetch the full contributor record
  /// to prefill the edit form.
  Future<void> _editContributor(ContributorBreakdownEntry entry) async {
    final Contributor existing;
    try {
      final contributors = await widget.api.listContributors(widget.collectionId);
      existing = contributors.firstWhere((c) => c.id == entry.contributorId);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
      return;
    }
    if (!mounted) return;
    final edited = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ContributorFormSheet(
        api: widget.api,
        collectionId: widget.collectionId,
        existing: existing,
      ),
    );
    if (edited == true) _dataKey.currentState?.reload();
  }

  /// Records a contribution with no M-PESA message behind it at all --
  /// e.g. money collected directly on the organizer's own phone number
  /// (so it can never generate a "you have received" SMS to themselves),
  /// or cash. Lets the amount and which period it counts toward be set
  /// directly, at any point -- not just during the initial list import
  /// (see ImportContributorsScreen, which uses the same backend endpoint
  /// for backfilling a pasted historical tracker).
  Future<void> _recordContribution(ContributorBreakdownEntry entry) async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecordContributionSheet(
        api: widget.api,
        collectionId: widget.collectionId,
        contributorId: entry.contributorId,
        contributorName: entry.name,
      ),
    );
    if (recorded == true) _dataKey.currentState?.reload();
  }

  Future<void> _importContributors() async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ImportContributorsScreen(api: widget.api, collectionId: widget.collectionId),
      ),
    );
    if (imported == true) _dataKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expected Contributors'),
        actions: [
          IconButton(
            onPressed: _importContributors,
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Import list',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContributor,
        icon: const Icon(Icons.add),
        label: const Text('Add Contributor'),
      ),
      body: SafeArea(
        child: AsyncDataView<CollectionReport>(
          key: _dataKey,
          loader: _load,
          builder: (context, report, refresh) {
            final entries = report.contributorBreakdown;
            if (entries.isEmpty) {
              return EmptyState(
                icon: Icons.people_outline,
                title: 'No contributors yet',
                subtitle: 'Add who you expect to contribute to this collection.',
                action: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: _addContributor,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Contributor'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _importContributors,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Import a list instead'),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => refresh(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  // The running target scales with how many weeks have
                  // actually been recorded so far; before any week is
                  // recorded, fall back to the flat per-week amount.
                  final targetAmount = entry.currentTargetAmount ?? entry.expectedAmount;
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _editContributor(entry),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(
                                    targetAmount != null
                                        ? '${formatKsh(entry.totalPaid)} of ${formatKsh(targetAmount)}'
                                        : formatKsh(entry.totalPaid),
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            StatusBadge.contributorPaid(entry.hasPaid),
                            IconButton(
                              onPressed: () => _recordContribution(entry),
                              icon: const Icon(Icons.payments_outlined, size: 20),
                              tooltip: 'Record a contribution (no M-PESA message)',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.edit_outlined, size: 18, color: Theme.of(context).colorScheme.outline),
                          ],
                        ),
                      ),
                    ),
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

/// Records a contribution directly against a known contributor with no
/// M-PESA message behind it -- confirmed immediately, since a human is
/// naming the contributor directly (see
/// reconciliation.record_manual_contribution). The date chosen here is
/// what the contribution counts toward in reports, exactly like
/// ReviewActionCard's/TransactionsScreen's "Edit period" pickers -- there
/// is no separate "real message time" to preserve for a manual entry.
class _RecordContributionSheet extends StatefulWidget {
  final ApiService api;
  final String collectionId;
  final String contributorId;
  final String contributorName;

  const _RecordContributionSheet({
    required this.api,
    required this.collectionId,
    required this.contributorId,
    required this.contributorName,
  });

  @override
  State<_RecordContributionSheet> createState() => _RecordContributionSheetState();
}

class _RecordContributionSheetState extends State<_RecordContributionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: 'Which period should this count toward?',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await widget.api.recordManualContribution(
        collectionId: widget.collectionId,
        contributorId: widget.contributorId,
        amount: int.parse(_amountController.text.trim().replaceAll(',', '')),
        timestamp: _date,
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
    final theme = Theme.of(context);
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
            Text('Record Contribution', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'For ${widget.contributorName} -- no M-PESA message needed. '
              'Use this when money was received directly (e.g. your own '
              'number, cash) and never generated a confirmation SMS.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Amount', prefixText: 'KSh '),
              autofocus: true,
              validator: (v) {
                final parsed = int.tryParse((v ?? '').replaceAll(',', ''));
                if (parsed == null) return 'Enter a whole number';
                if (parsed <= 0) return 'Amount must be greater than zero';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Counts toward ${formatDate(_date)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton(onPressed: _pickDate, child: const Text('Change')),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Record Contribution'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add-or-edit form for a contributor. In add mode (`existing == null`) it
/// creates a new row; in edit mode it PATCHes the given contributor's
/// name/expected_amount/phone -- the list (and every total derived from
/// it) can be corrected at any point in the collection's life, not just
/// at initial setup.
class _ContributorFormSheet extends StatefulWidget {
  final ApiService api;
  final String collectionId;
  final Contributor? existing;

  const _ContributorFormSheet({
    required this.api,
    required this.collectionId,
    this.existing,
  });

  @override
  State<_ContributorFormSheet> createState() => _ContributorFormSheetState();
}

class _ContributorFormSheetState extends State<_ContributorFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _amountController = TextEditingController(
    text: widget.existing?.expectedAmount?.toString() ?? '',
  );
  late final _phoneController = TextEditingController(text: widget.existing?.phone ?? '');
  bool _submitting = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final amountText = _amountController.text.trim().replaceAll(',', '');
      final phoneText = _phoneController.text.trim();
      if (_isEditing) {
        await widget.api.updateContributor(
          collectionId: widget.collectionId,
          contributorId: widget.existing!.id,
          name: _nameController.text.trim(),
          expectedAmount: amountText.isEmpty ? null : int.parse(amountText),
          phone: phoneText.isEmpty ? null : phoneText,
        );
      } else {
        await widget.api.createContributor(
          collectionId: widget.collectionId,
          name: _nameController.text.trim(),
          expectedAmount: amountText.isEmpty ? null : int.parse(amountText),
          phone: phoneText,
        );
      }
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
            Text(
              _isEditing ? 'Edit Contributor' : 'Add Contributor',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Expected amount (optional)', prefixText: 'KSh '),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final parsed = int.tryParse(v.replaceAll(',', ''));
                if (parsed == null) return 'Enter a whole number';
                if (parsed < 0) return 'Cannot be negative';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)', hintText: '2547XXXXXXXX'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isEditing ? 'Save Changes' : 'Add Contributor'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
