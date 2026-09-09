import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../utils/format.dart';
import '../../widgets/async_data_view.dart';

class CreateCollectionScreen extends StatefulWidget {
  final ApiService api;
  final String projectId;
  final bool suggestMain;

  const CreateCollectionScreen({
    super.key,
    required this.api,
    required this.projectId,
    required this.suggestMain,
  });

  @override
  State<CreateCollectionScreen> createState() => _CreateCollectionScreenState();
}

class _CreateCollectionScreenState extends State<CreateCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  late CollectionType _type;
  late final TextEditingController _nameController;
  final _targetController = TextEditingController();
  DateTime _date = DateTime.now();
  PeriodType _period = PeriodType.weekly;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _type = widget.suggestMain ? CollectionType.main : CollectionType.harambee;
    _nameController = TextEditingController(
      text: widget.suggestMain ? 'Main Contribution' : 'Harambee',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _onTypeChanged(CollectionType type) {
    setState(() {
      _type = type;
      if (type == CollectionType.main && _nameController.text.isEmpty) {
        _nameController.text = 'Main Contribution';
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final targetText = _targetController.text.trim().replaceAll(',', '');
      await widget.api.createCollection(
        projectId: widget.projectId,
        type: _type,
        name: _nameController.text.trim(),
        targetAmount: targetText.isEmpty ? null : int.parse(targetText),
        date: _type == CollectionType.harambee ? _date : null,
        period: _period,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Add Collection')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<CollectionType>(
                  segments: const [
                    ButtonSegment(
                      value: CollectionType.main,
                      label: Text('Main Contribution'),
                      icon: Icon(Icons.account_balance_wallet),
                    ),
                    ButtonSegment(
                      value: CollectionType.harambee,
                      label: Text('Harambee'),
                      icon: Icon(Icons.local_fire_department),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => _onTypeChanged(s.first),
                ),
                const SizedBox(height: 20),
                const Text('Name'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: _type == CollectionType.harambee ? 'e.g. Saturday Harambee' : null,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 20),
                const Text('Target amount (optional)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(prefixText: 'KSh ', hintText: '50000'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final parsed = int.tryParse(v.replaceAll(',', ''));
                    if (parsed == null) return 'Enter a whole number';
                    if (parsed < 0) return 'Target amount cannot be negative';
                    return null;
                  },
                ),
                if (_type == CollectionType.harambee) ...[
                  const SizedBox(height: 20),
                  const Text('Date'),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(formatDate(_date)),
                  ),
                ] else ...[
                  const SizedBox(height: 20),
                  const Text('How often does this group contribute?'),
                  const SizedBox(height: 6),
                  SegmentedButton<PeriodType>(
                    segments: const [
                      ButtonSegment(value: PeriodType.weekly, label: Text('Weekly')),
                      ButtonSegment(value: PeriodType.fortnightly, label: Text('Fortnightly')),
                      ButtonSegment(value: PeriodType.monthly, label: Text('Monthly')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (s) => setState(() => _period = s.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Drives missing-period nudges, catch-up payment splitting, and '
                    'weekly-amount pattern detection during bulk import.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Create Collection'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
