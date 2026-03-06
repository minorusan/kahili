import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';
import '../theme/kahili_theme.dart';
import 'widgets/shared_widgets.dart';

class DevelopAskPage extends StatefulWidget {
  const DevelopAskPage({super.key});

  @override
  State<DevelopAskPage> createState() => _DevelopAskPageState();
}

class _DevelopAskPageState extends State<DevelopAskPage> {
  final _requestCtrl = TextEditingController();
  bool _submitting = false;
  bool _completed = false;
  DevelopAgentStatus? _status;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkExistingAgent();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _requestCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingAgent() async {
    try {
      final status = await ApiClient.getDevelopAgentStatus();
      if (status.active && mounted) {
        setState(() {
          _submitting = true;
          _status = status;
          _requestCtrl.text = status.request ?? '';
        });
        _startPolling();
      }
    } catch (_) {}
  }

  Future<void> _submitRequest() async {
    final request = _requestCtrl.text.trim();
    if (request.isEmpty) return;

    setState(() => _submitting = true);

    try {
      await ApiClient.startDevelopAgent(request);
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
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
      final status = await ApiClient.getDevelopAgentStatus();
      if (!mounted) return;
      setState(() => _status = status);

      if (!status.active) {
        _pollTimer?.cancel();
        setState(() {
          _submitting = false;
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
        title: const Text('Feature Request',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: KahiliColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KahiliColors.cyan.withAlpha(10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KahiliColors.cyan.withAlpha(30)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.info_outline, size: 16, color: KahiliColors.cyan),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The agent will implement your feature within the Kahili repo, '
                    'build, commit, and restart. Be specific to avoid rejection.',
                    style: TextStyle(
                      fontSize: 12,
                      color: KahiliColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Request input
          const Text(
            'Feature Description',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KahiliColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _requestCtrl,
            maxLines: 6,
            minLines: 3,
            enabled: !_submitting && !_completed,
            style:
                const TextStyle(fontSize: 14, color: KahiliColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Describe the feature you want implemented...',
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

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _submitting || _completed ? null : _submitRequest,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.rocket_launch, size: 20),
              label: Text(
                _submitting
                    ? 'Agent is implementing...'
                    : (_completed ? 'Done' : 'Submit Request'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _completed ? KahiliColors.emerald : KahiliColors.flame,
                foregroundColor: Colors.black,
                disabledBackgroundColor:
                    _submitting ? KahiliColors.goldMuted : KahiliColors.emerald,
                disabledForegroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Status / Report area
          if (_submitting || _completed) _statusArea(),
        ],
      ),
    );
  }

  Widget _statusArea() {
    final statusText = _status?.statusText ?? 'Evaluating feature request...';

    if (_submitting) {
      final elapsed = _formatElapsed();
      final previewLines =
          statusText.split('\n').where((l) => l.trim().isNotEmpty).toList();
      final preview = previewLines.length > 8
          ? previewLines.sublist(previewLines.length - 8).join('\n')
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

    // Completed / rejected / failed
    final isRejected = _status?.status == 'rejected';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isRejected) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: KahiliColors.flame.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: KahiliColors.flame.withAlpha(40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.block, size: 16, color: KahiliColors.flame),
                    SizedBox(width: 8),
                    Text(
                      'REQUEST REJECTED',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: KahiliColors.flame,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _status?.rejectionReason ?? statusText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: KahiliColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              _status?.status == 'failed' ? 'Error' : 'Implementation Report',
              style: const TextStyle(
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
            child: CopyableSelectionArea(
              child: MarkdownBody(
                data: statusText,
                styleSheet: _markdownStyle(),
              ),
            ),
          ),
        ],
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
