import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import 'async_data_view.dart';

void showWhatsappSheet({
  required BuildContext context,
  required ApiService api,
  required String collectionId,
  required CollectionType type,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WhatsappSheet(api: api, collectionId: collectionId, type: type),
  );
}

class _Kind {
  final String key;
  final String label;
  const _Kind(this.key, this.label);
}

class _WhatsappSheet extends StatefulWidget {
  final ApiService api;
  final String collectionId;
  final CollectionType type;

  const _WhatsappSheet({required this.api, required this.collectionId, required this.type});

  @override
  State<_WhatsappSheet> createState() => _WhatsappSheetState();
}

class _WhatsappSheetState extends State<_WhatsappSheet> {
  late List<_Kind> _kinds;
  late String _selectedKind;

  @override
  void initState() {
    super.initState();
    _kinds = [
      if (widget.type == CollectionType.harambee) const _Kind('harambee', 'Progress'),
      const _Kind('full', 'Full Update'),
      const _Kind('weekly', 'Weekly'),
      const _Kind('paid', 'Paid'),
      const _Kind('pending', 'Pending'),
      const _Kind('review', 'Issues'),
    ];
    _selectedKind = _kinds.first.key;
  }

  Future<String> _load() => widget.api.getWhatsappText(widget.collectionId, _selectedKind);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('WhatsApp Update', style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _kinds
                        .map(
                          (kind) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(kind.label),
                              selected: _selectedKind == kind.key,
                              onSelected: (_) => setState(() => _selectedKind = kind.key),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AsyncDataView<String>(
                    key: ValueKey(_selectedKind),
                    loader: _load,
                    builder: (context, text, refresh) {
                      return SingleChildScrollView(
                        controller: scrollController,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: SelectableText(
                            text,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      try {
                        final text = await widget.api.getWhatsappText(widget.collectionId, _selectedKind);
                        await Clipboard.setData(ClipboardData(text: text));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        showErrorSnackBar(context, e);
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
