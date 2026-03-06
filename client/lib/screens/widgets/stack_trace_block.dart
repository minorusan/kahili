import 'package:flutter/material.dart';
import '../../models/mother_issue.dart';
import '../../theme/kahili_theme.dart';

class StackTraceBlock extends StatelessWidget {
  final List<StackFrame> frames;

  const StackTraceBlock({super.key, required this.frames});

  @override
  Widget build(BuildContext context) {
    final appFrameCount = frames.where((f) => f.inApp).length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF08080E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KahiliColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: KahiliColors.surfaceBright,
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                const Icon(Icons.layers, size: 14, color: KahiliColors.textTertiary),
                const SizedBox(width: 6),
                Text(
                  '${frames.length} frames',
                  style: const TextStyle(fontSize: 12, color: KahiliColors.textSecondary),
                ),
                if (appFrameCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(color: KahiliColors.textTertiary, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: KahiliColors.flame,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$appFrameCount in-app',
                    style: const TextStyle(fontSize: 12, color: KahiliColors.flame),
                  ),
                ],
              ],
            ),
          ),

          // Frames
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: frames.asMap().entries.map((entry) {
                final frame = entry.value;
                final isApp = frame.inApp;
                final hasFile = frame.filename.isNotEmpty;

                // Build display string
                String display;
                if (hasFile) {
                  display = '${frame.filename}:${frame.lineno} in ${frame.function}';
                } else {
                  display = frame.function;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Frame number
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${entry.key}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: KahiliColors.textTertiary,
                          ),
                        ),
                      ),
                      // In-app indicator bar
                      if (isApp)
                        Container(
                          width: 3,
                          height: 16,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: KahiliColors.flame,
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        )
                      else
                        const SizedBox(width: 11),
                      // Frame text
                      Expanded(
                        child: Text(
                          display,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: isApp ? KahiliColors.gold : KahiliColors.textTertiary,
                            fontWeight: isApp ? FontWeight.w500 : FontWeight.w400,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
