import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../models/mpesa_sms.dart';
import '../../services/api_service.dart';
import '../../services/sms_inbox_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';
import '../transactions/reconciliation_result_screen.dart';

enum _ImportStatus { notImported, imported, needsReview }

enum _Filter { all, unimported, imported, needsReview }

/// The M-PESA Inbox: browse M-PESA messages already sitting in the
/// phone's SMS inbox (never a live listener -- see SmsInboxService),
/// select some, and import them as structured transaction candidates
/// through the existing backend pipeline. See task section 19: this
/// screen is a *local phone data source* feeding the existing import/
/// reconciliation flow, not a second backend or a second reconciliation
/// system.
class MpesaInboxScreen extends StatefulWidget {
  final ApiService api;
  final String collectionId;

  /// Injectable so tests can substitute a fake without touching the real
  /// SMS/permission platform channels. Defaults to the real device
  /// implementation.
  final SmsInboxService? smsService;

  /// Set when this screen was opened from a real-time SMS alert (see
  /// SmsAlertService) for a specific message -- scrolls to and visually
  /// highlights that message once the inbox loads. The default filter
  /// (All) already shows it regardless of import status.
  final String? highlightTransactionCode;

  const MpesaInboxScreen({
    super.key,
    required this.api,
    required this.collectionId,
    this.smsService,
    this.highlightTransactionCode,
  });

  @override
  State<MpesaInboxScreen> createState() => _MpesaInboxScreenState();
}

class _MpesaInboxScreenState extends State<MpesaInboxScreen> {
  late final SmsInboxService _smsService = widget.smsService ?? SmsInboxService();
  final _dataKey = GlobalKey<AsyncDataViewState<_InboxData>>();

  SmsAccessState? _accessState;
  bool _checkingPermission = true;
  bool _selectionMode = false;
  bool _importing = false;
  final Set<String> _selectedIds = {};
  _Filter _filter = _Filter.all;
  final GlobalKey _highlightedTileKey = GlobalKey();
  bool _scrolledToHighlight = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final state = await _smsService.checkPermission();
    if (!mounted) return;
    setState(() {
      _accessState = state;
      _checkingPermission = false;
    });
  }

  Future<void> _requestPermission() async {
    final state = await _smsService.requestPermission();
    if (!mounted) return;
    setState(() => _accessState = state);
  }

  Future<_InboxData> _load() async {
    final results = await _smsService.loadMpesaMessages();
    final transactions = await widget.api.listTransactions(widget.collectionId);
    final importedCodes = {for (final t in transactions) t.mpesaCode};
    return _InboxData(messages: results, importedCodes: importedCodes);
  }

  _ImportStatus _statusFor(MpesaSmsResult msg, Set<String> importedCodes) {
    if (msg.kind == MpesaSmsKind.unparsed) return _ImportStatus.needsReview;
    if (msg.transactionCode != null && importedCodes.contains(msg.transactionCode)) {
      return _ImportStatus.imported;
    }
    return _ImportStatus.notImported;
  }

  List<MpesaSmsResult> _applyFilter(List<MpesaSmsResult> messages, Set<String> importedCodes) {
    if (_filter == _Filter.all) return messages;
    return messages.where((m) {
      final status = _statusFor(m, importedCodes);
      switch (_filter) {
        case _Filter.unimported:
          return status == _ImportStatus.notImported;
        case _Filter.imported:
          return status == _ImportStatus.imported;
        case _Filter.needsReview:
          return status == _ImportStatus.needsReview;
        case _Filter.all:
          return true;
      }
    }).toList();
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAllImportable(List<MpesaSmsResult> visible, Set<String> importedCodes) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..addAll(
          visible
              .where((m) => m.isImportable && _statusFor(m, importedCodes) == _ImportStatus.notImported)
              .map((m) => m.id),
        );
    });
  }

  Future<void> _showRawSms(MpesaSmsResult msg) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RawSmsSheet(message: msg),
    );
  }

  Future<void> _importSelected(List<MpesaSmsResult> selected) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ImportPreviewDialog(messages: selected),
    );
    if (confirmed != true) return;

    setState(() => _importing = true);
    var successCount = 0;
    var failureCount = 0;

    for (final msg in selected) {
      try {
        await widget.api.createTransaction(
          collectionId: widget.collectionId,
          mpesaCode: msg.transactionCode!,
          senderName: msg.senderName!,
          amount: msg.amount!,
          senderPhone: msg.senderPhone,
          timestamp: msg.timestamp,
        );
        successCount++;
      } catch (_) {
        failureCount++;
      }
    }

    if (!mounted) return;
    setState(() {
      _importing = false;
      _selectedIds.clear();
      _selectionMode = false;
    });

    if (successCount == 0) {
      showErrorSnackBar(context, ApiException('Could not import any transactions. Check your connection and try again.'));
      _dataKey.currentState?.reload();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failureCount == 0
              ? '$successCount transaction${successCount == 1 ? '' : 's'} imported'
              : '$successCount imported, $failureCount failed -- reselect and try again',
        ),
      ),
    );

    // Reuse the existing reconciliation pipeline/screen -- no second
    // reconciliation system.
    try {
      final decisions = await widget.api.reconcile(widget.collectionId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReconciliationResultScreen(
            api: widget.api,
            collectionId: widget.collectionId,
            decisions: decisions,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
    }

    if (!mounted) return;
    _dataKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('M-PESA Inbox'),
        actions: [
          IconButton(
            onPressed: _checkingPermission ? null : () => _dataKey.currentState?.reload(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          if (_accessState == SmsAccessState.granted)
            TextButton(
              onPressed: _toggleSelectionMode,
              child: Text(_selectionMode ? 'Cancel' : 'Select'),
            ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
      bottomNavigationBar: (_selectionMode && _selectedIds.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _importing ? null : () => _importFromCurrentData(),
                  icon: _importing
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_done),
                  label: Text('Import Selected (${_selectedIds.length})'),
                ),
              ),
            )
          : null,
    );
  }

  List<MpesaSmsResult>? _lastVisibleMessages;

  void _scheduleHighlightScroll(List<MpesaSmsResult> visible) {
    if (_scrolledToHighlight || widget.highlightTransactionCode == null) return;
    if (!visible.any((m) => m.transactionCode == widget.highlightTransactionCode)) return;
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

  Future<void> _importFromCurrentData() async {
    final visible = _lastVisibleMessages;
    if (visible == null) return;
    final selected = visible.where((m) => _selectedIds.contains(m.id)).toList();
    await _importSelected(selected);
  }

  Widget _buildBody(BuildContext context) {
    if (_checkingPermission) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (_accessState) {
      case SmsAccessState.unavailable:
        return _NoPhoneSmsState(onRefresh: _checkPermission);
      case SmsAccessState.denied:
        return _PermissionRequestCard(onGrant: _requestPermission);
      case SmsAccessState.permanentlyDenied:
        return _PermissionRequestCard(onGrant: openAppSettings, permanentlyDenied: true);
      case SmsAccessState.granted:
        return AsyncDataView<_InboxData>(
          key: _dataKey,
          loader: _load,
          errorHint: 'Could not load or import M-PESA messages. Check your connection.',
          builder: (context, data, refresh) {
            final visible = _applyFilter(data.messages, data.importedCodes);
            _lastVisibleMessages = visible;
            _scheduleHighlightScroll(visible);

            return RefreshIndicator(
              onRefresh: () async => refresh(),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${data.messages.length} M-PESA message${data.messages.length == 1 ? '' : 's'} found',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (_selectionMode)
                          TextButton(
                            onPressed: () => _selectAllImportable(visible, data.importedCodes),
                            child: const Text('Select all'),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(label: 'All', selected: _filter == _Filter.all, onTap: () => setState(() => _filter = _Filter.all)),
                          _FilterChip(label: 'Unimported', selected: _filter == _Filter.unimported, onTap: () => setState(() => _filter = _Filter.unimported)),
                          _FilterChip(label: 'Imported', selected: _filter == _Filter.imported, onTap: () => setState(() => _filter = _Filter.imported)),
                          _FilterChip(label: 'Needs Review', selected: _filter == _Filter.needsReview, onTap: () => setState(() => _filter = _Filter.needsReview)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: visible.isEmpty
                        ? (data.messages.isEmpty
                            ? _NoPhoneSmsState(onRefresh: () async => refresh())
                            : EmptyState(
                                icon: Icons.filter_alt_off_outlined,
                                title: 'No messages match this filter',
                              ))
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final msg = visible[index];
                              final status = _statusFor(msg, data.importedCodes);
                              final isHighlighted = widget.highlightTransactionCode != null &&
                                  msg.transactionCode == widget.highlightTransactionCode;
                              return _MessageTile(
                                key: isHighlighted ? _highlightedTileKey : null,
                                message: msg,
                                status: status,
                                selectionMode: _selectionMode,
                                selected: _selectedIds.contains(msg.id),
                                highlighted: isHighlighted,
                                onTap: () {
                                  if (_selectionMode) {
                                    if (status == _ImportStatus.notImported && msg.isImportable) {
                                      _toggleSelected(msg.id);
                                    }
                                  } else {
                                    _showRawSms(msg);
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      case null:
        return const Center(child: CircularProgressIndicator());
    }
  }
}

class _InboxData {
  final List<MpesaSmsResult> messages;
  final Set<String> importedCodes;
  _InboxData({required this.messages, required this.importedCodes});
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
    );
  }
}

class _PermissionRequestCard extends StatelessWidget {
  final Future<void> Function() onGrant;
  final bool permanentlyDenied;

  const _PermissionRequestCard({required this.onGrant, this.permanentlyDenied = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sms_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'SMS permission needed',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              permanentlyDenied
                  ? 'You previously denied SMS access. Open Settings and allow SMS '
                      'permission for ChangaSmart to read your M-PESA messages.'
                  : 'ChangaSmart reads M-PESA messages already in your phone\'s SMS '
                      'inbox so you can import them as contributions. It only asks for '
                      'SMS read access -- nothing else, and nothing leaves your phone '
                      'until you choose to import a specific message.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onGrant,
              icon: Icon(permanentlyDenied ? Icons.settings : Icons.lock_open),
              label: Text(permanentlyDenied ? 'Open Settings' : 'Grant SMS Permission'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPhoneSmsState extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _NoPhoneSmsState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_read_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No phone SMS available',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Connect a physical Android phone and grant SMS permission to '
              'read your M-PESA messages.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  final MpesaSmsResult message;
  final _ImportStatus status;
  final bool selectionMode;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;

  const _MessageTile({
    super.key,
    required this.message,
    required this.status,
    required this.selectionMode,
    required this.selected,
    this.highlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSelect = status == _ImportStatus.notImported && message.isImportable;

    return Card(
      color: highlighted ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: highlighted
              ? theme.colorScheme.primary
              : selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
          width: highlighted || selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 4),
                  child: Checkbox(
                    value: selected,
                    onChanged: canSelect ? (_) => onTap() : null,
                  ),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _relativeDayTime(message.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message.amount != null ? '${formatKsh(message.amount!)} received' : 'Amount unknown',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'From: ${message.senderName ?? 'Unknown'}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      'Code: ${message.transactionCode ?? 'not found'}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    _StatusChip(status: status),
                    if (message.kind == MpesaSmsKind.unparsed && message.reason != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        message.reason!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final _ImportStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final IconData icon;
    late final Color color;
    switch (status) {
      case _ImportStatus.imported:
        label = 'Already imported';
        icon = Icons.check_circle;
        color = AppColors.confirmed;
        break;
      case _ImportStatus.needsReview:
        label = 'Needs review';
        icon = Icons.error_outline;
        color = AppColors.needsReview;
        break;
      case _ImportStatus.notImported:
        label = 'Not imported';
        icon = Icons.radio_button_unchecked;
        color = AppColors.pending;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

class _RawSmsSheet extends StatelessWidget {
  final MpesaSmsResult message;
  const _RawSmsSheet({required this.message});

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.message_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Raw SMS', style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Shown locally on this device only -- never uploaded.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (message.address != null) ...[
            Text('From address: ${message.address}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
          Text(_relativeDayTime(message.timestamp, includeDate: true), style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(message.rawBody, style: theme.textTheme.bodyMedium),
          ),
          if (message.isImportable) ...[
            const SizedBox(height: 16),
            _DetailRow(label: 'Parsed amount', value: formatKsh(message.amount!)),
            _DetailRow(label: 'Parsed sender', value: message.senderName!),
            _DetailRow(label: 'Parsed code', value: message.transactionCode!),
            if (message.senderPhone != null) _DetailRow(label: 'Parsed phone', value: message.senderPhone!),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _ImportPreviewDialog extends StatelessWidget {
  final List<MpesaSmsResult> messages;
  const _ImportPreviewDialog({required this.messages});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Import ${messages.length} M-PESA transaction${messages.length == 1 ? '' : 's'}?'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: messages
              .map(
                (m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check, size: 16, color: AppColors.confirmed),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${formatKsh(m.amount!)} — ${m.senderName!}')),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
      ],
    );
  }
}

String _relativeDayTime(DateTime dt, {bool includeDate = false}) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final diff = today.difference(that).inDays;

  final time = formatDateTime(local).split(', ').last;
  if (!includeDate) {
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
  }
  return formatDateTime(local);
}
