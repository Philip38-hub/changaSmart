import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const StatusBadge({super.key, required this.label, required this.color, required this.icon});

  factory StatusBadge.transaction(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.confirmed:
        return StatusBadge(label: 'Confirmed', color: AppColors.confirmed, icon: Icons.check_circle);
      case TransactionStatus.needsReview:
        return StatusBadge(label: 'Needs review', color: AppColors.needsReview, icon: Icons.error_outline);
      case TransactionStatus.pending:
        return StatusBadge(label: 'Pending', color: AppColors.pending, icon: Icons.schedule);
      case TransactionStatus.matched:
        return StatusBadge(label: 'Matched', color: AppColors.confirmed, icon: Icons.check_circle_outline);
      case TransactionStatus.ignored:
        return const StatusBadge(label: 'Ignored', color: AppColors.pending, icon: Icons.block);
      case TransactionStatus.unknown:
        return const StatusBadge(label: 'Unknown', color: AppColors.pending, icon: Icons.help_outline);
    }
  }

  factory StatusBadge.contributorPaid(bool hasPaid) {
    return hasPaid
        ? const StatusBadge(label: 'Paid', color: AppColors.confirmed, icon: Icons.check_circle)
        : const StatusBadge(label: 'Pending', color: AppColors.pending, icon: Icons.schedule);
  }

  factory StatusBadge.collectionStatus(CollectionStatus status) {
    return status == CollectionStatus.closed
        ? const StatusBadge(label: 'Closed', color: AppColors.pending, icon: Icons.lock)
        : const StatusBadge(label: 'Active', color: AppColors.confirmed, icon: Icons.bolt);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
