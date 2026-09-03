import 'package:flutter/material.dart';

import '../utils/format.dart';

/// The "KSh 82,000 raised, of KSh 150,000, progress bar, 54.7%" block used
/// on the project dashboard and collection screen.
class ProgressSummary extends StatelessWidget {
  final int raised;
  final int? target;
  final int? remaining;
  final double progress;
  final Color? accentColor;

  const ProgressSummary({
    super.key,
    required this.raised,
    required this.target,
    required this.remaining,
    required this.progress,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accentColor ?? theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatKsh(raised),
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          'raised',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (target != null) ...[
          const SizedBox(height: 12),
          Text('of ${formatKsh(target!)}', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatPercent(progress),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (remaining != null)
                Text(
                  '${formatKsh(remaining!)} remaining',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
