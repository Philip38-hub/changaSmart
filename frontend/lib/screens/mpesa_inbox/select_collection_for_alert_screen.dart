import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/async_data_view.dart';
import 'mpesa_inbox_screen.dart';

/// Shown when a real-time SMS alert's candidate matching genuinely tied
/// across more than one of the user's active collections (see
/// SmsAlertService._findBestMatch) -- rather than guessing which one the
/// message belongs to, this lets the user pick, then opens that
/// collection's M-PESA Inbox with the message still pre-highlighted.
class SelectCollectionForAlertScreen extends StatelessWidget {
  final ApiService api;
  final String? highlightTransactionCode;

  const SelectCollectionForAlertScreen({
    super.key,
    required this.api,
    this.highlightTransactionCode,
  });

  Future<List<_Entry>> _load() async {
    final projects = await api.listProjects();
    final entries = <_Entry>[];
    for (final project in projects) {
      if (project.status != ProjectStatus.active) continue;
      final collections = await api.listCollections(project.id);
      for (final collection in collections) {
        if (collection.status != CollectionStatus.active) continue;
        entries.add(_Entry(project: project, collection: collection));
      }
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Which collection is this for?')),
      body: SafeArea(
        child: AsyncDataView<List<_Entry>>(
          loader: _load,
          builder: (context, entries, refresh) {
            if (entries.isEmpty) {
              return const EmptyState(
                icon: Icons.folder_open,
                title: 'No active collections',
                subtitle: 'There is nothing to import this message into right now.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    title: Text(entry.collection.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(entry.project.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => MpesaInboxScreen(
                          api: api,
                          collectionId: entry.collection.id,
                          highlightTransactionCode: highlightTransactionCode,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Entry {
  final Project project;
  final Collection collection;
  _Entry({required this.project, required this.collection});
}
