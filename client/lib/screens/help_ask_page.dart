import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';
import '../theme/kahili_theme.dart';

class HelpAskPage extends StatefulWidget {
  const HelpAskPage({super.key});

  @override
  State<HelpAskPage> createState() => _HelpAskPageState();
}

class _HelpAskPageState extends State<HelpAskPage> {
  final _questionCtrl = TextEditingController();
  bool _asking = false;
  bool _completed = false;
  HelpAgentStatus? _status;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkExistingAgent();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _questionCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingAgent() async {
    try {
      final status = await ApiClient.getHelpAgentStatus();
      if (status.active && mounted) {
        setState(() {
          _asking = true;
          _status = status;
          _questionCtrl.text = status.question ?? '';
        });
        _startPolling();
      }
    } catch (_) {}
  }

  Future<void> _askAgent() async {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty) return;

    setState(() => _asking = true);

    try {
      await ApiClient.startHelpAgent(question);
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() => _asking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _startPolling() {
    _pollStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollStatus();
    });
  }

  Future<void> _pollStatus() async {
    try {
      final status = await ApiClient.getHelpAgentStatus();
      if (!mounted) return;
      setState(() => _status = status);

      if (!status.active) {
        _pollTimer?.cancel();
        setState(() {
          _asking = false;
          _completed = true;
        });
      }
    } catch (_) {}
  }

  String _formatElapsed() {
    if (_status?.startedAt == null) return '';
    final start = DateTime.tryParse(_status!.startedAt!);
    if (start == null) return '';
    final elapsed = DateTime.now().toUtc().difference(start);
    return '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KahiliColors.bg,
      appBar: AppBar(
        title: const Text('Ask Kahili',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: KahiliColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Question input
          const Text(
            'Your Question',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KahiliColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _questionCtrl,
            maxLines: 4,
            minLines: 2,
            enabled: !_asking && !_completed,
            style:
                const TextStyle(fontSize: 14, color: KahiliColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Ask about Kahili...',
              hintStyle: const TextStyle(color: KahiliColors.textTertiary),
              filled: true,
              fillColor: KahiliColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: KahiliColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: KahiliColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: KahiliColors.flame),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: KahiliColors.border),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Ask button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _asking || _completed ? null : _askAgent,
              icon: _asking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.auto_awesome, size: 20),
              label: Text(
                _asking
                    ? 'Agent is thinking...'
                    : (_completed ? 'Done' : 'Ask Agent'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _completed ? KahiliColors.emerald : KahiliColors.flame,
                foregroundColor: Colors.black,
                disabledBackgroundColor:
                    _asking ? KahiliColors.goldMuted : KahiliColors.emerald,
                disabledForegroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Status / Answer area
          if (_asking || _completed) _statusArea(),
        ],
      ),
    );
  }

  Widget _statusArea() {
    final statusText = _status?.statusText ?? 'Waiting for agent...';

    // While running — show progress panel (same pattern as investigation)
    if (_asking) {
      final elapsed = _formatElapsed();
      final previewLines =
          statusText.split('\n').where((l) => l.trim().isNotEmpty).toList();
      final preview = previewLines.length > 6
          ? previewLines.sublist(previewLines.length - 6).join('\n')
          : previewLines.join('\n');

      return Container(
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: KahiliColors.gold.withAlpha(12),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: KahiliColors.gold),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Agent is working...',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: KahiliColors.gold,
                    ),
                  ),
                  const Spacer(),
                  if (elapsed.isNotEmpty)
                    Text(
                      elapsed,
                      style: const TextStyle(
                        fontSize: 12,
                        color: KahiliColors.textTertiary,
                        fontFamily: 'monospace',
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
                'Polling every 5s...',
                style:
                    TextStyle(fontSize: 10, color: KahiliColors.textTertiary),
              ),
            ),
          ],
        ),
      );
    }

    // Completed — show formatted markdown answer
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          child: SelectionArea(
            child: MarkdownBody(
              data: statusText,
              styleSheet: _markdownStyle(),
            ),
          ),
        ),
      ],
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
