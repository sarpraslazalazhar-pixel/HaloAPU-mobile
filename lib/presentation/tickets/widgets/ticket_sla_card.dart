import 'package:flutter/material.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';

class TicketSlaCard extends StatelessWidget {
  final TicketModel ticket;

  const TicketSlaCard({super.key, required this.ticket});

  @override
  Widget build(BuildContext context) {
    final responseTime = ticket.slaResponseTime;
    final resolutionTime = ticket.slaResolutionTime;
    final isBreached = ticket.isSlaBreached;
    final isPaused = ticket.isSlaPaused;

    // Sembunyikan jika tidak ada data SLA dan tidak breach/pause
    if (responseTime == null && resolutionTime == null && !isBreached && !isPaused) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBreached
              ? AppTheme.danger.withValues(alpha: 0.25)
              : (isPaused
                  ? AppTheme.warning.withValues(alpha: 0.25)
                  : const Color(0xFFE2E8F0)),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isBreached
                      ? AppTheme.danger.withValues(alpha: 0.1)
                      : (isPaused
                          ? AppTheme.warning.withValues(alpha: 0.12)
                          : AppTheme.oceanWater.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isBreached
                      ? Icons.timer_off_outlined
                      : (isPaused ? Icons.pause_circle_outline_rounded : Icons.timer_outlined),
                  size: 17,
                  color: isBreached
                      ? AppTheme.danger
                      : (isPaused ? AppTheme.warning : AppTheme.oceanWater),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Service Level Agreement (SLA)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              if (isBreached)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.22),
                      width: 1.0,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 12, color: AppTheme.danger),
                      SizedBox(width: 4),
                      Text(
                        'SLA Terlewat',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.danger,
                        ),
                      ),
                    ],
                  ),
                )
              else if (isPaused)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.25),
                      width: 1.0,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pause_circle_outline_rounded, size: 12, color: AppTheme.warning),
                      SizedBox(width: 4),
                      Text(
                        'SLA Dijeda',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.warning,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (responseTime != null || resolutionTime != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Row(
                children: [
                  if (responseTime != null)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: AppTheme.oceanWater.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.reply_rounded,
                              size: 13,
                              color: AppTheme.oceanWater,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Target Respon',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.slateGrey,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  responseTime,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (responseTime != null && resolutionTime != null)
                    Container(
                      width: 1,
                      height: 32,
                      color: const Color(0xFFE2E8F0),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  if (resolutionTime != null)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.task_alt_rounded,
                              size: 13,
                              color: AppTheme.success,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Target Resolusi',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.slateGrey,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  resolutionTime,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
