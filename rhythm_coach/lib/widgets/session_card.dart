import 'package:flutter/material.dart';

import '../models/session.dart';
import '../theme/app_theme.dart';

class SessionCard extends StatelessWidget {
  final Session session;
  final VoidCallback onTap;

  const SessionCard({
    super.key,
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.fitness_center,
                  color: AppTheme.accent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.formattedDuration,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (session.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        session.description,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
