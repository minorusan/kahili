import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';
import '../theme/kahili_theme.dart';

class HelpDetailPage extends StatefulWidget {
  final String questionId;

  const HelpDetailPage({super.key, required this.questionId});

  @override
  State<HelpDetailPage> createState() => _HelpDetailPageState();
}

class _HelpDetailPageState extends State<HelpDetailPage> {
  HelpQuestionDetail? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await ApiClient.getHelpQuestion(widget.questionId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
        '${_pad(local.hour)}:${_pad(local.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KahiliColors.bg,
      appBar: AppBar(
        title: const Text('Help Answer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: KahiliColors.border),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _detail == null
              ? const Center(
                  child: Text('Question not found',
                      style: TextStyle(color: KahiliColors.textSecondary)))
              : SelectionArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Question card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: KahiliColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: KahiliColors.flame.withAlpha(40)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.help_outline,
                                    size: 16, color: KahiliColors.flame),
                                const SizedBox(width: 8),
                                const Text(
                                  'QUESTION',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: KahiliColors.flame,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _formatDate(_detail!.startedAt),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: KahiliColors.textTertiary,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _detail!.question,
                              style: const TextStyle(
                                fontSize: 14,
                                color: KahiliColors.textPrimary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Answer
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8, left: 4),
                        child: Text(
                          'Answer',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: KahiliColors.textSecondary,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: KahiliColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: KahiliColors.border),
                        ),
                        child: MarkdownBody(
                          data: _detail!.answer.isNotEmpty
                              ? _detail!.answer
                              : 'No answer available.',
                          styleSheet: _markdownStyle(),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  MarkdownStyleSheet _markdownStyle() {
    return MarkdownStyleSheet(
      h1: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: KahiliColors.textPrimary,
          height: 1.4),
      h2: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: KahiliColors.flame,
          height: 1.5),
      h3: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: KahiliColors.textPrimary,
          height: 1.4),
      p: const TextStyle(
          fontSize: 13,
          color: KahiliColors.textPrimary,
          height: 1.6),
      strong: const TextStyle(
          fontWeight: FontWeight.w700, color: KahiliColors.textPrimary),
      em: const TextStyle(
          fontStyle: FontStyle.italic, color: KahiliColors.textSecondary),
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
      listBullet: const TextStyle(color: KahiliColors.flame),
      a: const TextStyle(
          color: KahiliColors.cyan, decoration: TextDecoration.underline),
      horizontalRuleDecoration: const BoxDecoration(
        border:
            Border(top: BorderSide(color: KahiliColors.border, width: 1)),
      ),
      blockquoteDecoration: BoxDecoration(
        border: const Border(
            left: BorderSide(color: KahiliColors.flame, width: 3)),
        color: KahiliColors.flame.withAlpha(8),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
      h2Padding: const EdgeInsets.only(top: 16, bottom: 4),
      h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
      pPadding: const EdgeInsets.only(bottom: 8),
    );
  }
}
