import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../widgets/async_data_view.dart';
import 'project_dashboard_screen.dart';

class CreateProjectScreen extends StatefulWidget {
  final ApiService api;

  const CreateProjectScreen({super.key, required this.api});

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Project name is required';
    return null;
  }

  String? _validateTarget(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    final parsed = int.tryParse(value.replaceAll(',', ''));
    if (parsed == null) return 'Enter a whole number';
    if (parsed < 0) return 'Target amount cannot be negative';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final targetText = _targetController.text.trim().replaceAll(',', '');
      final project = await widget.api.createProject(
        name: _nameController.text.trim(),
        targetAmount: targetText.isEmpty ? null : int.parse(targetText),
      );
      if (!mounted) return;
      // Replace this form with the new project's dashboard, and let Home
      // know (via pop(true) further up the stack when the user backs out)
      // that it should refresh its list.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ProjectDashboardScreen(api: widget.api, project: project),
        ),
      );
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
      appBar: AppBar(title: const Text('Create Contribution')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Project name'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: "e.g. Mama Jane Medical Fund"),
                  validator: _validateName,
                  autofocus: true,
                ),
                const SizedBox(height: 20),
                const Text('Target amount (optional)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(prefixText: 'KSh ', hintText: '150000'),
                  validator: _validateTarget,
                ),
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
                        : const Text('Create Project'),
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
