import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Loads [future] and renders loading / error+retry / data states
/// consistently across every API-driven screen. Pull-to-refresh re-runs
/// the loader. This is the one place "what does a failed API call look
/// like" is decided, so every screen behaves the same way.
class AsyncDataView<T> extends StatefulWidget {
  final Future<T> Function() loader;
  final Widget Function(BuildContext context, T data, VoidCallback refresh) builder;
  final String errorHint;

  const AsyncDataView({
    super.key,
    required this.loader,
    required this.builder,
    this.errorHint = 'Check that the backend is running and reachable.',
  });

  @override
  State<AsyncDataView<T>> createState() => AsyncDataViewState<T>();
}

class AsyncDataViewState<T> extends State<AsyncDataView<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  /// Public so a parent screen can force a reload (e.g. after an action
  /// completes elsewhere) via a `GlobalKey<AsyncDataViewState<T>>`.
  void reload() {
    // Block body is deliberate: `() => _future = widget.loader()` would
    // make this closure *return* the assignment's value (a Future), and
    // setState's debug-mode guard throws on that -- which means
    // markNeedsBuild() never runs, so the fetch happens but the screen
    // never redraws. Caught via real device testing, not static analysis.
    setState(() {
      _future = widget.loader();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorView(
            message: snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Something went wrong.',
            hint: widget.errorHint,
            onRetry: reload,
          );
        }
        return widget.builder(context, snapshot.data as T, reload);
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final String hint;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.hint, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple empty-state placeholder for lists with no data yet.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// A snackbar helper so error handling after a button tap (create,
/// reconcile, resolve-review, ...) is consistent everywhere.
void showErrorSnackBar(BuildContext context, Object error) {
  final message = error is ApiException ? error.message : 'Something went wrong.';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
}
