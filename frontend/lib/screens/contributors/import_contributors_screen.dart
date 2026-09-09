import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/contributor_list_parser.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';

/// Bulk-import a contributor list from a pasted WhatsApp-style list or CSV
/// (see ContributorListParser). Mirrors the M-PESA Inbox's select/preview/
/// confirm/summarize shape, but imports in one API call since a real bulk
/// endpoint exists here (unlike per-transaction M-PESA import).
class ImportContributorsScreen extends StatefulWidget {
  final ApiService api;
  final String collectionId;

  const ImportContributorsScreen({super.key, required this.api, required this.collectionId});

  @override
  State<ImportContributorsScreen> createState() => _ImportContributorsScreenState();
}

class _ImportContributorsScreenState extends State<ImportContributorsScreen> {
  final _textController = TextEditingController();
  List<Contributor>? _existingContributors;
  ContributorListParseResult? _parsed;
  final Set<int> _excludedIndices = {};
  bool _includeHistorical = false;
  bool _importing = false;
  int? _weeklyTargetToApply;
  bool _weeklyTargetPromptDismissed = false;

  @override
  void initState() {
    super.initState();
    widget.api.listContributors(widget.collectionId).then((list) {
      if (mounted) setState(() => _existingContributors = list);
    }).catchError((_) {
      if (mounted) setState(() => _existingContributors = const []);
    });
    // The "Parse" button's enabled state depends on _textController.text,
    // which is read directly in build() -- without this listener, typing
    // never triggers a rebuild and the button stays stuck disabled.
    _textController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Set<String> get _existingNormalizedNames => {
        for (final c in _existingContributors ?? const <Contributor>[])
          c.name.trim().toLowerCase(),
      };

  void _parse() {
    final result = ContributorListParser.parse(_textController.text);
    setState(() {
      _parsed = result;
      _excludedIndices.clear();
      _includeHistorical = false;
      _weeklyTargetToApply = null;
      _weeklyTargetPromptDismissed = false;
    });
  }

  void _reset() {
    setState(() {
      _parsed = null;
      _excludedIndices.clear();
    });
  }

  Future<void> _import() async {
    final parsed = _parsed;
    if (parsed == null) return;
    final selected = [
      for (var i = 0; i < parsed.contributors.length; i++)
        if (!_excludedIndices.contains(i)) parsed.contributors[i],
    ];
    if (selected.isEmpty) return;

    setState(() => _importing = true);
    try {
      final result = await widget.api.bulkImportContributors(
        collectionId: widget.collectionId,
        rows: [
          for (final row in selected)
            (
              name: row.name,
              // A row's own explicit amount (from a CSV column) always
              // wins; the detected weekly target only fills in for rows
              // that don't have one.
              expectedAmount: row.expectedAmount ?? _weeklyTargetToApply,
              phone: row.phone,
            ),
        ],
      );

      var historicalCount = 0;
      if (_includeHistorical && parsed.weeklyEntries.isNotEmpty) {
        final idByName = <String, String>{
          for (final c in _existingContributors ?? const <Contributor>[])
            c.name.trim().toLowerCase(): c.id,
          for (final c in result.created) c.name.trim().toLowerCase(): c.id,
        };
        for (final entry in parsed.weeklyEntries) {
          final contributorId = idByName[entry.name.trim().toLowerCase()];
          if (contributorId == null) continue;
          try {
            await widget.api.recordManualContribution(
              collectionId: widget.collectionId,
              contributorId: contributorId,
              amount: entry.amount,
              timestamp: entry.weekStart,
            );
            historicalCount++;
          } catch (_) {
            // Best-effort backfill -- one failed historical entry doesn't
            // block the rest; the contributor list import already
            // succeeded regardless.
          }
        }
      }

      if (!mounted) return;
      final parts = <String>[
        '${result.created.length} contributor${result.created.length == 1 ? '' : 's'} added',
        if (result.skippedNames.isNotEmpty) '${result.skippedNames.length} skipped (already exist)',
        if (historicalCount > 0) '$historicalCount historical record${historicalCount == 1 ? '' : 's'} added',
      ];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(parts.join(', '))));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    return Scaffold(
      appBar: AppBar(title: const Text('Import Contributors')),
      body: SafeArea(child: parsed == null ? _buildInput(context) : _buildPreview(context, parsed)),
      bottomNavigationBar: parsed == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _importing || _excludedIndices.length == parsed.contributors.length
                      ? null
                      : _import,
                  icon: _importing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_done),
                  label: Text(
                    'Import (${parsed.contributors.length - _excludedIndices.length})',
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildInput(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Paste a WhatsApp-style list (one name per line, numbered or not) '
            'or CSV content (name, amount, phone). No target amount is required.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '1. Jane Wanjiku\n2. Peter Otieno\n3. Sarcastic',
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _textController.text.trim().isEmpty ? null : _parse,
            icon: const Icon(Icons.checklist),
            label: const Text('Parse'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context, ContributorListParseResult parsed) {
    if (parsed.contributors.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No names found',
        subtitle: "Couldn't find any contributor names in that text.",
        action: OutlinedButton(onPressed: _reset, child: const Text('Try again')),
      );
    }
    final existing = _existingNormalizedNames;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${parsed.contributors.length} name${parsed.contributors.length == 1 ? '' : 's'} found',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(onPressed: _reset, child: const Text('Start over')),
            ],
          ),
        ),
        if (parsed.detectedWeeklyAmount != null &&
            _weeklyTargetToApply == null &&
            !_weeklyTargetPromptDismissed)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Card(
              color: AppColors.confirmed.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppColors.confirmed.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Looks like this group contributes '
                      '${formatKsh(parsed.detectedWeeklyAmount!)} weekly. Set '
                      'this as everyone\'s expected weekly amount?',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _weeklyTargetPromptDismissed = true),
                          child: const Text('No thanks'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: () => setState(
                            () => _weeklyTargetToApply = parsed.detectedWeeklyAmount,
                          ),
                          child: Text('Set ${formatKsh(parsed.detectedWeeklyAmount!)} as target'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_weeklyTargetToApply != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: AppColors.confirmed),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${formatKsh(_weeklyTargetToApply!)} weekly target will be applied to '
                    'contributors without one.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _weeklyTargetToApply = null),
                  child: const Text('Undo'),
                ),
              ],
            ),
          ),
        if (parsed.hasWeeklyData)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeHistorical,
              onChanged: (v) => setState(() => _includeHistorical = v ?? false),
              title: Text(
                'Also import each week\'s amount as a historical record '
                '(${parsed.weeklyEntries.length} entries, no M-PESA message needed)',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            itemCount: parsed.contributors.length,
            itemBuilder: (context, index) {
              final row = parsed.contributors[index];
              final isDuplicate = existing.contains(row.name.trim().toLowerCase());
              final excluded = _excludedIndices.contains(index);
              final effectiveAmount = row.expectedAmount ?? _weeklyTargetToApply;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: CheckboxListTile(
                  value: !excluded,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _excludedIndices.remove(index);
                    } else {
                      _excludedIndices.add(index);
                    }
                  }),
                  title: Text(row.name),
                  subtitle: Wrap(
                    spacing: 8,
                    children: [
                      if (effectiveAmount != null) Text('Expected ${formatKsh(effectiveAmount)}'),
                      if (isDuplicate)
                        Text(
                          'Already in this list',
                          style: TextStyle(color: AppColors.needsReview),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
