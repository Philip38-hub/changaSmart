import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';

/// Week-by-week contribution breakdown for a recurring collection, with an
/// "All weeks" view (the default) and the ability to drill into one week --
/// the "filter by time" view alongside the copy-paste "Weekly" WhatsApp
/// export (see widgets/whatsapp_sheet.dart).
class WeeklyReportScreen extends StatefulWidget {
  final ApiService api;
  final String collectionId;

  const WeeklyReportScreen({super.key, required this.api, required this.collectionId});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  final _dataKey = GlobalKey<AsyncDataViewState<WeeklyCollectionReport>>();
  DateTime? _selectedWeekStart;

  Future<WeeklyCollectionReport> _load() => widget.api.getWeeklyReport(widget.collectionId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly Breakdown')),
      body: SafeArea(
        child: AsyncDataView<WeeklyCollectionReport>(
          key: _dataKey,
          loader: _load,
          builder: (context, report, refresh) {
            if (report.weeks.isEmpty) {
              return const EmptyState(
                icon: Icons.calendar_month_outlined,
                title: 'No weekly contributions yet',
                subtitle: 'Confirmed contributions will show up here grouped by week.',
              );
            }
            final weeksToShow = _selectedWeekStart == null
                ? report.weeks
                : report.weeks.where((w) => w.weekStart == _selectedWeekStart).toList();
            return RefreshIndicator(
              onRefresh: () async => refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  Text('Total: ${formatKsh(report.grandTotal)}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text('All weeks'),
                            selected: _selectedWeekStart == null,
                            onSelected: (_) => setState(() => _selectedWeekStart = null),
                          ),
                        ),
                        for (final week in report.weeks)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_weekLabel(week)),
                              selected: _selectedWeekStart == week.weekStart,
                              onSelected: (_) => setState(() => _selectedWeekStart = week.weekStart),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final week in weeksToShow) ...[
                    Text(_weekLabel(week), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          for (final entry in week.contributions)
                            ListTile(title: Text(entry.name), trailing: Text(formatKsh(entry.amount))),
                          ListTile(
                            title: const Text('Weekly total', style: TextStyle(fontWeight: FontWeight.w700)),
                            trailing: Text(
                              formatKsh(week.weeklyTotal),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _weekLabel(WeeklyBreakdownEntry week) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(week.weekStart.day)}/${two(week.weekStart.month)} - '
        '${two(week.weekEnd.day)}/${two(week.weekEnd.month)}';
  }
}
