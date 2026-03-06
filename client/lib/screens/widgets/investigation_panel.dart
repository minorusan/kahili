import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../models/api_models.dart';
import '../../theme/kahili_theme.dart';
import 'shared_widgets.dart';

class InvestigationPanel extends StatelessWidget {
  final bool reportLoading;
  final bool isInvestigating;
  final String? report;
  final InvestigationStatus? investigationStatus;
  final VoidCallback onInvestigate;

  const InvestigationPanel({
    super.key,
    required this.reportLoading,
    required this.isInvestigating,
    required this.report,
    required this.investigationStatus,
    required this.onInvestigate,
  });

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (reportLoading) {
      return darkCard(
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }

    // Active investigation — show status panel
    if (isInvestigating) {
      return _investigationStatusPanel();
    }

    // Report exists — show it in collapsible
    if (report != null && report!.isNotEmpty) {
      // Extract TLDR section for collapsed preview
      final tldr = _extractTldr(report!);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: KahiliColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: KahiliColors.border),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding: EdgeInsets.zero,
                collapsedIconColor: KahiliColors.textTertiary,
                iconColor: KahiliColors.flame,
                title: Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 16, color: KahiliColors.flame),
                    const SizedBox(width: 8),
                    const Text(
                      'Investigation Report',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KahiliColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                subtitle: tldr != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          tldr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: KahiliColors.textTertiary,
                            height: 1.4,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : null,
                children: [
                  const Divider(height: 1, color: KahiliColors.border),
                  _reportBlock(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onInvestigate,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Restart Investigation'),
              style: OutlinedButton.styleFrom(
                foregroundColor: KahiliColors.flame,
                side: const BorderSide(color: KahiliColors.flame, width: 1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      );
    }

    // No report, no investigation — show investigate button
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: onInvestigate,
        icon: const Icon(Icons.search, size: 20),
        label: const Text(
          'Investigate',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: KahiliColors.flame,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _investigationStatusPanel() {
    final elapsed = investigationStatus!.startedAt != null
        ? DateTime.now()
            .toUtc()
            .difference(DateTime.parse(investigationStatus!.startedAt!))
        : null;
    final elapsedStr = elapsed != null
        ? '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s'
        : '';

    // Show last few lines of the report as live preview
    final lastReport = investigationStatus!.lastReport ?? '';
    final previewLines = lastReport.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final preview = previewLines.length > 6
        ? previewLines.sublist(previewLines.length - 6).join('\n')
        : previewLines.join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeader('Investigation In Progress'),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: KahiliColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KahiliColors.gold.withAlpha(60)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: KahiliColors.gold.withAlpha(12),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: KahiliColors.gold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Agent is investigating...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KahiliColors.gold,
                      ),
                    ),
                    const Spacer(),
                    if (elapsedStr.isNotEmpty)
                      Text(
                        elapsedStr,
                        style: const TextStyle(fontSize: 12, color: KahiliColors.textTertiary, fontFamily: 'monospace'),
                      ),
                  ],
                ),
              ),

              // Branch info
              if (investigationStatus!.branch != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.commit, size: 14, color: KahiliColors.textTertiary),
                      const SizedBox(width: 6),
                      Text(
                        investigationStatus!.branch!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: KahiliColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

              // Live preview
              if (preview.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF08080E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      preview,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: KahiliColors.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),

              // Polling hint
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Text(
                  'Polling every 30s...',
                  style: TextStyle(fontSize: 10, color: KahiliColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reportBlock() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      child: MarkdownBody(
        data: report!,
        styleSheet: MarkdownStyleSheet(
          // Headings
          h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: KahiliColors.textPrimary, height: 1.4),
          h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: KahiliColors.flame, height: 1.5),
          h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: KahiliColors.textPrimary, height: 1.4),
          // Body
          p: const TextStyle(fontSize: 13, color: KahiliColors.textPrimary, height: 1.6),
          strong: const TextStyle(fontWeight: FontWeight.w700, color: KahiliColors.textPrimary),
          em: const TextStyle(fontStyle: FontStyle.italic, color: KahiliColors.textSecondary),
          // Code
          code: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: KahiliColors.cyan,
            backgroundColor: KahiliColors.surfaceBright,
          ),
          codeblockDecoration: BoxDecoration(
            color: const Color(0xFF08080E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KahiliColors.border),
          ),
          codeblockPadding: const EdgeInsets.all(12),
          codeblockAlign: WrapAlignment.start,
          // Lists
          listBullet: const TextStyle(color: KahiliColors.flame),
          // Links
          a: const TextStyle(color: KahiliColors.cyan, decoration: TextDecoration.underline),
          // Dividers
          horizontalRuleDecoration: const BoxDecoration(
            border: Border(top: BorderSide(color: KahiliColors.border, width: 1)),
          ),
          // Block quote
          blockquoteDecoration: BoxDecoration(
            border: const Border(left: BorderSide(color: KahiliColors.flame, width: 3)),
            color: KahiliColors.flame.withAlpha(8),
          ),
          blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          // Spacing
          h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
          h2Padding: const EdgeInsets.only(top: 16, bottom: 4),
          h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
          pPadding: const EdgeInsets.only(bottom: 8),
        ),
      ),
    );
  }

  static String? _extractTldr(String report) {
    final lines = report.split('\n');
    int start = -1;
    for (int i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9#\s]'), '');
      if (lower.startsWith('##') && (lower.contains('tldr') || lower.contains('tl dr') || lower.contains('summary'))) {
        start = i + 1;
        break;
      }
    }
    if (start < 0) return null;
    final buf = StringBuffer();
    for (int i = start; i < lines.length; i++) {
      if (lines[i].startsWith('##')) break;
      final trimmed = lines[i].replaceFirst(RegExp(r'^[-*]\s*'), '').trim();
      if (trimmed.isNotEmpty) {
        if (buf.isNotEmpty) buf.write('\n');
        buf.write(trimmed);
      }
    }
    final result = buf.toString().trim();
    return result.isEmpty ? null : result;
  }
}
