import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';
import '../theme/kahili_theme.dart';
import 'widgets/shared_widgets.dart';
import 'develop_ask_page.dart';

class DevelopDetailPage extends StatefulWidget {
  final String requestId;

  const DevelopDetailPage({super.key, required this.requestId});

  @override
  State<DevelopDetailPage> createState() => _DevelopDetailPageState();
}

class _DevelopDetailPageState extends State<DevelopDetailPage> {
  DevelopRequestDetail? _detail;
  bool _loading = true;
  final _retryCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _retryCtrl.dispose();
    super.dispose();
  }

  Future<void> _retryWithContext() async {
    final extra = _retryCtrl.text.trim();
    if (extra.isEmpty) return;

    final combinedRequest =
        '${_detail!.request}\n\nADDITIONAL CONTEXT (previous attempt was rejected: ${_detail!.rejectionReason ?? _detail!.report}):\n$extra';

    setState(() => _submitting = true);
    try {
      await ApiClient.startDevelopAgent(combinedRequest);
      if (!mounted) return;
      // Pop detail page and push ask page to watch progress
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DevelopAskPage()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _load() async {
    try {
      final detail = await ApiClient.getDevelopRequest(widget.requestId);
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
        title: const Text('Feature Details',
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
                  child: Text('Request not found',
                      style: TextStyle(color: KahiliColors.textSecondary)))
              : CopyableSelectionArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Request card
                      _requestCard(),
                      const SizedBox(height: 16),

                      // Status badge
                      _statusBadge(),
                      const SizedBox(height: 16),

                      // Report or rejection
                      if (_detail!.status == 'rejected') ...[
                        _rejectionCard(),
                        const SizedBox(height: 16),
                        _retrySection(),
                      ] else
                        _reportCard(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _requestCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KahiliColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KahiliColors.flame.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build_outlined,
                  size: 16, color: KahiliColors.flame),
              const SizedBox(width: 8),
              const Text(
                'FEATURE REQUEST',
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
            _detail!.request,
            style: const TextStyle(
              fontSize: 14,
              color: KahiliColors.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge() {
    final Color color;
    final IconData icon;
    final String label;

    switch (_detail!.status) {
      case 'completed':
        color = KahiliColors.emerald;
        icon = Icons.check_circle;
        label = 'IMPLEMENTED';
        break;
      case 'rejected':
        color = KahiliColors.flame;
        icon = Icons.block;
        label = 'REJECTED';
        break;
      case 'running':
        color = KahiliColors.gold;
        icon = Icons.hourglass_top;
        label = 'IN PROGRESS';
        break;
      default:
        color = KahiliColors.error;
        icon = Icons.error_outline;
        label = 'FAILED';
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (_detail!.commitHash != null) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: KahiliColors.surfaceBright,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _detail!.commitHash!.substring(0, 7),
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: KahiliColors.cyan,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _rejectionCard() {
    return Container(
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
          const Text(
            'Rejection Reason',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KahiliColors.flame,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _detail!.rejectionReason ?? _detail!.report,
            style: const TextStyle(
              fontSize: 13,
              color: KahiliColors.textPrimary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            'Implementation Report',
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
            data: _detail!.report.isNotEmpty
                ? _detail!.report
                : 'No report available.',
            styleSheet: _markdownStyle(),
          ),
        ),
      ],
    );
  }

  Widget _retrySection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KahiliColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KahiliColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Retry with more detail',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KahiliColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _retryCtrl,
            maxLines: 4,
            minLines: 2,
            enabled: !_submitting,
            style: const TextStyle(fontSize: 14, color: KahiliColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Clarify what was ambiguous...',
              hintStyle: const TextStyle(color: KahiliColors.textTertiary),
              filled: true,
              fillColor: const Color(0xFF08080E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: KahiliColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: KahiliColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: KahiliColors.flame),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: KahiliColors.border),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _retryWithContext,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.replay, size: 18),
              label: Text(
                _submitting ? 'Starting...' : 'Retry',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: KahiliColors.flame,
                foregroundColor: Colors.black,
                disabledBackgroundColor: KahiliColors.goldMuted,
                disabledForegroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
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
