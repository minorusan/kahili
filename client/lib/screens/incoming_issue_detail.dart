import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';
import '../models/sentry_issue.dart';
import '../theme/kahili_theme.dart';
import 'widgets/stack_trace_block.dart';
import 'widgets/shared_widgets.dart';

class IncomingIssueDetail extends StatefulWidget {
  final SentryIssue issue;

  const IncomingIssueDetail({super.key, required this.issue});

  @override
  State<IncomingIssueDetail> createState() => _IncomingIssueDetailState();
}

class _IncomingIssueDetailState extends State<IncomingIssueDetail> {
  final _promptController = TextEditingController();
  bool _creating = false;
  bool _generating = false;
  String? _statusText;
  String? _resultStatus;
  Timer? _pollTimer;

  @override
  void dispose() {
    _promptController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
        '${_pad(local.hour)}:${_pad(local.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _formatCount(String n) {
    final v = int.tryParse(n) ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return n;
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _createManualMotherIssue() async {
    setState(() => _creating = true);
    try {
      final mi = await ApiClient.createManualMotherIssue(widget.issue.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mother issue created: ${mi.title.split('\n').first}'),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  Future<void> _startGeneration() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _generating = true;
      _statusText = 'Starting rule generation...';
      _resultStatus = null;
    });

    try {
      await ApiClient.startRuleGeneration(prompt);
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _statusText = 'Error: $e';
          _resultStatus = 'failed';
        });
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final status = await ApiClient.getRuleGenerationStatus();
      if (!mounted) return;

      setState(() {
        _statusText = status.lastStatus ?? _statusText;
      });

      if (!status.active) {
        _pollTimer?.cancel();
        setState(() {
          _generating = false;
          _resultStatus = status.status ?? 'completed';
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    final levelColor = KahiliColors.levelColor(issue.level);
    final shortTitle = issue.title.split('\n').first;

    return Scaffold(
      backgroundColor: KahiliColors.bg,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: levelColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              issue.shortId,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: KahiliColors.textSecondary,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: KahiliColors.border),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _creating ? null : _createManualMotherIssue,
        backgroundColor: _creating ? KahiliColors.surfaceBright : KahiliColors.flame,
        child: _creating
            ? const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
              )
            : const Icon(Icons.add, color: Colors.black),
      ),
      body: CopyableSelectionArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Title block ─────────────────────────────────
          _titleBlock(shortTitle, levelColor),
          const SizedBox(height: 16),

          // ── Error detail ────────────────────────────────
          if (issue.errorType != null || issue.errorValue != null)  ...[
            _errorDetailBlock(),
            const SizedBox(height: 16),
          ],

          // ── Metrics ─────────────────────────────────────
          _metricsRow(),
          const SizedBox(height: 16),

          // ── Timeline ────────────────────────────────────
          sectionHeader('Timeline'),
          darkCard(
            child: Column(
              children: [
                timelineRow('First seen', _formatDate(issue.firstSeen), KahiliColors.emerald),
                kahiliDivider(),
                timelineRow('Last seen', _formatDate(issue.lastSeen), KahiliColors.flame),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Stack trace ─────────────────────────────────
          if (issue.stackFrames != null && issue.stackFrames!.isNotEmpty) ...[
            sectionHeader('Stack Trace'),
            StackTraceBlock(frames: issue.stackFrames!),
            const SizedBox(height: 16),
          ],

          // ── Sentry link ─────────────────────────────────
          if (issue.permalink.isNotEmpty) ...[
            sectionHeader('Sentry Link'),
            darkCard(
              child: InkWell(
                onTap: () => launchUrl(Uri.parse(issue.permalink), mode: LaunchMode.externalApplication),
                onLongPress: () => _copy(issue.permalink),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.open_in_new, size: 16, color: KahiliColors.cyanMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          issue.permalink,
                          style: const TextStyle(fontSize: 12, color: KahiliColors.cyan, fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _copy(issue.permalink),
                        child: const Icon(Icons.copy_rounded, size: 14, color: KahiliColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Rule generation ─────────────────────────────
          sectionHeader('Create Grouping Rule'),
          _ruleGenerationSection(),
          const SizedBox(height: 40),
        ],
      )),
    );
  }

  Widget _titleBlock(String shortTitle, Color levelColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KahiliColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KahiliColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: levelColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: levelColor.withAlpha(60)),
                ),
                child: Text(
                  widget.issue.level.toUpperCase(),
                  style: TextStyle(fontSize: 10, color: levelColor, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: KahiliColors.textTertiary.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KahiliColors.textTertiary.withAlpha(40)),
                ),
                child: const Text(
                  'UNGROUPED',
                  style: TextStyle(fontSize: 10, color: KahiliColors.textTertiary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            shortTitle,
            style: const TextStyle(
              color: KahiliColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorDetailBlock() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KahiliColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KahiliColors.error.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.issue.errorType != null)
            Text(
              widget.issue.errorType!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: KahiliColors.flame,
                fontFamily: 'monospace',
              ),
            ),
          if (widget.issue.errorValue != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.issue.errorValue!,
              style: const TextStyle(
                fontSize: 12,
                color: KahiliColors.textSecondary,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricsRow() {
    return Row(
      children: [
        _metricTile(Icons.local_fire_department, KahiliColors.flame,
            _formatCount(widget.issue.count), 'Events'),
        const SizedBox(width: 8),
        _metricTile(Icons.people, KahiliColors.cyanMuted,
            widget.issue.userCount.toString(), 'Users'),
      ],
    );
  }

  Widget _metricTile(IconData icon, Color iconColor, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: KahiliColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KahiliColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: KahiliColors.textPrimary)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: KahiliColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  Widget _ruleGenerationSection() {
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
            'Describe the grouping rule for this type of issue:',
            style: TextStyle(fontSize: 13, color: KahiliColors.textSecondary),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _promptController,
            enabled: !_generating,
            maxLines: 4,
            style: const TextStyle(fontSize: 14, color: KahiliColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. "Group all NullReferenceException errors by their top in-app stack frame"',
              hintStyle: const TextStyle(color: KahiliColors.textTertiary, fontSize: 13),
              filled: true,
              fillColor: KahiliColors.surfaceBright,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: KahiliColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: KahiliColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: KahiliColors.flame),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),

          // Status text
          if (_statusText != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF08080E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_generating)
                    const Padding(
                      padding: EdgeInsets.only(right: 8, top: 2),
                      child: SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: KahiliColors.gold),
                      ),
                    )
                  else if (_resultStatus == 'completed')
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.check_circle, size: 16, color: KahiliColors.emerald),
                    )
                  else if (_resultStatus == 'failed' || _resultStatus == 'rejected')
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.error, size: 16, color: KahiliColors.error),
                    ),
                  Expanded(
                    child: Text(
                      _statusText!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _resultStatus == 'completed'
                            ? KahiliColors.emerald
                            : _resultStatus == 'failed' || _resultStatus == 'rejected'
                                ? KahiliColors.error
                                : KahiliColors.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _generating || _resultStatus == 'completed'
                  ? null
                  : _startGeneration,
              icon: _generating
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                    )
                  : _resultStatus == 'completed'
                      ? const Icon(Icons.check, size: 20)
                      : const Icon(Icons.auto_fix_high, size: 20),
              label: Text(
                _generating
                    ? 'Generating...'
                    : _resultStatus == 'completed'
                        ? 'Rule Created'
                        : 'Create Rule',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _resultStatus == 'completed'
                    ? KahiliColors.emerald
                    : KahiliColors.flame,
                foregroundColor: Colors.black,
                disabledBackgroundColor: _resultStatus == 'completed'
                    ? KahiliColors.emerald.withAlpha(180)
                    : KahiliColors.surfaceBright,
                disabledForegroundColor: _resultStatus == 'completed'
                    ? Colors.black
                    : KahiliColors.textTertiary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
