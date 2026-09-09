import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';

/// Period-by-period contribution breakdown for a recurring collection, with
/// an "All periods" view (the default) and the ability to drill into one
/// period -- the "filter by time" view alongside the copy-paste "Periods"
/// WhatsApp export (see widgets/whatsapp_sheet.dart). "Period" follows the
/// collection's own configured cadence (Collection.period): weekly,
/// fortnightly, or monthly.
class PeriodReportScreen extends StatefulWidget {
  final ApiService api;
  final String collectionId;

  const PeriodReportScreen({super.key, required this.api, required this.collectionId});

  @override
  State<PeriodReportScreen> createState() => _PeriodReportScreenState();
}

class _PeriodData {
  final PeriodType period;
  final PeriodCollectionReport report;
  _PeriodData({required this.period, required this.report});
}

class _PeriodReportScreenState extends State<PeriodReportScreen> {
  final _dataKey = GlobalKey<AsyncDataViewState<_PeriodData>>();
  DateTime? _selectedPeriodStart;

  Future<_PeriodData> _load() async {
    final collection = await widget.api.getCollection(widget.collectionId);
    final report = await widget.api.getPeriodReport(widget.collectionId);
    return _PeriodData(period: collection.period, report: report);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Period Breakdown')),
      body: SafeArea(
        child: AsyncDataView<_PeriodData>(
          key: _dataKey,
          loader: _load,
          builder: (context, data, refresh) {
            final label = _periodLabel(data.period);
            final periods = data.report.periods;
            if (periods.isEmpty) {
              return EmptyState(
                icon: Icons.calendar_month_outlined,
                title: 'No ${label.toLowerCase()} contributions yet',
                subtitle: 'Confirmed contributions will show up here grouped by ${label.toLowerCase()}.',
              );
            }
            final toShow = _selectedPeriodStart == null
                ? periods
                : periods.where((p) => p.periodStart == _selectedPeriodStart).toList();
            return RefreshIndicator(
              onRefresh: () async => refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  Text('Total: ${formatKsh(data.report.grandTotal)}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('All ${label.toLowerCase()}s'),
                            selected: _selectedPeriodStart == null,
                            onSelected: (_) => setState(() => _selectedPeriodStart = null),
                          ),
                        ),
                        for (final period in periods)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_periodRangeLabel(period)),
                              selected: _selectedPeriodStart == period.periodStart,
                              onSelected: (_) => setState(() => _selectedPeriodStart = period.periodStart),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final period in toShow) ...[
                    Text(
                      '$label of ${_periodRangeLabel(period)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          for (final entry in period.contributions)
                            ListTile(title: Text(entry.name), trailing: Text(formatKsh(entry.amount))),
                          ListTile(
                            title: Text('${label}ly total', style: const TextStyle(fontWeight: FontWeight.w700)),
                            trailing: Text(
                              formatKsh(period.periodTotal),
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

  String _periodLabel(PeriodType period) {
    switch (period) {
      case PeriodType.fortnightly:
        return 'Fortnight';
      case PeriodType.monthly:
        return 'Month';
      case PeriodType.weekly:
      case PeriodType.unknown:
        return 'Week';
    }
  }

  String _periodRangeLabel(PeriodBreakdownEntry period) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(period.periodStart.day)}/${two(period.periodStart.month)} - '
        '${two(period.periodEnd.day)}/${two(period.periodEnd.month)}';
  }
}
