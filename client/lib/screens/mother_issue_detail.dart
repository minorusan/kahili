import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';
import '../models/mother_issue.dart';
import '../theme/kahili_theme.dart';
import '../utils/web_download.dart';
import 'investigate_dialog.dart';
import 'archive_dialog.dart';
import 'widgets/shared_widgets.dart';
import 'widgets/stack_trace_block.dart';
import 'widgets/child_issues_section.dart';
import 'widgets/investigation_panel.dart';

class MotherIssueDetail extends StatefulWidget {
  final MotherIssue issue;

  const MotherIssueDetail({super.key, required this.issue});

  @override
  State<MotherIssueDetail> createState() => _MotherIssueDetailState();
}

class _MotherIssueDetailState extends State<MotherIssueDetail> {
  String? _report;
  bool _reportLoading = true;

  InvestigationStatus? _investigationStatus;
  Timer? _pollTimer;

  // Child issues section key for clearing selection
  final GlobalKey<State> _childIssuesKey = GlobalKey<State>();

  // Child status sync
  Timer? _syncTimer;

  // Rule regeneration
  late TextEditingController _ruleController;
  String _originalRuleDescription = '';
  String _ruleLogic = '';
  bool _ruleLoading = true;
  bool _regenerating = false;
  RuleGenerationStatus? _regenStatus;
  Timer? _regenPollTimer;

  @override
  void initState() {
    super.initState();
    _ruleController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _regenPollTimer?.cancel();
    _syncTimer?.cancel();
    _ruleController.dispose();
    // Fire-and-forget: sync child statuses from Sentry when page closes
    ApiClient.syncMotherIssue(widget.issue.id);
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadReport(), _pollInvestigation(), _loadRuleDescription()]);
    _startPollingIfNeeded();
    _syncChildStatuses();
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) => _syncChildStatuses());
  }

  Future<void> _syncChildStatuses() async {
    try {
      final fresh = await ApiClient.getMotherIssue(widget.issue.id);
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < fresh.childStatuses.length && i < widget.issue.childStatuses.length; i++) {
          widget.issue.childStatuses[i] = fresh.childStatuses[i];
        }
        widget.issue.allChildrenArchived = fresh.allChildrenArchived;
      });
    } catch (_) {}
  }

  Future<void> _loadRuleDescription() async {
    try {
      final rules = await ApiClient.getRules();
      final match = rules.where((r) => r['name'] == widget.issue.ruleName);
      if (match.isNotEmpty && mounted) {
        setState(() {
          _originalRuleDescription = match.first['description'] ?? '';
          _ruleLogic = match.first['logic'] ?? '';
          _ruleController.text = _originalRuleDescription;
          _ruleLoading = false;
        });
      } else if (mounted) {
        setState(() => _ruleLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _ruleLoading = false);
    }
  }

  Future<void> _regenerateRule() async {
    final prompt = _ruleController.text.trim();
    if (prompt.isEmpty) return;

    setState(() => _regenerating = true);

    try {
      await ApiClient.regenerateRule(
        ruleName: widget.issue.ruleName,
        prompt: prompt,
      );
      // Start polling for generation status
      _pollRegenStatus();
      _regenPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _pollRegenStatus();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _regenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _pollRegenStatus() async {
    try {
      final status = await ApiClient.getRuleGenerationStatus();
      if (!mounted) return;
      setState(() => _regenStatus = status);

      if (!status.active) {
        _regenPollTimer?.cancel();
        setState(() => _regenerating = false);
        if (status.status == 'completed') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Rule regenerated. Issues re-processed.')),
            );
            // Pop back — this mother issue may no longer exist
            Navigator.of(context).pop(true);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadReport() async {
    try {
      final result = await ApiClient.getReport(widget.issue.id);
      if (mounted) {
        setState(() {
          _report = result.exists ? result.report : null;
          _reportLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _reportLoading = false);
    }
  }

  Future<void> _pollInvestigation() async {
    try {
      final status = await ApiClient.getInvestigationStatus();
      if (!mounted) return;
      setState(() {
        if (status.active && status.motherIssueId == widget.issue.id) {
          _investigationStatus = status;
        } else if (status.motherIssueId == widget.issue.id && !status.active) {
          // Investigation just finished — reload report
          _investigationStatus = null;
          _loadReport();
        } else {
          _investigationStatus = null;
        }
      });
    } catch (_) {}
  }

  void _startPollingIfNeeded() {
    _pollTimer?.cancel();
    if (_investigationStatus != null && _investigationStatus!.active) {
      _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _pollInvestigation().then((_) {
          if (_investigationStatus == null || !_investigationStatus!.active) {
            _pollTimer?.cancel();
          }
        });
      });
    }
  }

  Future<void> _openInvestigateDialog() async {
    final started = await InvestigateDialog.show(
      context,
      motherIssueId: widget.issue.id,
      issueTitle: widget.issue.title,
    );
    if (started && mounted) {
      await _pollInvestigation();
      _startPollingIfNeeded();
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

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }

  String _formatNumber(int number) {
    final str = number.toString();
    final result = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) result.write(',');
      result.write(str[i]);
    }
    return result.toString();
  }

  void _shareAsMarkdown() {
    final issue = widget.issue;
    final buf = StringBuffer();

    // Title
    buf.writeln('# ${issue.title.split('\n').first}');
    buf.writeln();

    // Summary table
    buf.writeln('## Summary');
    buf.writeln();
    buf.writeln('| Field | Value |');
    buf.writeln('|-------|-------|');
    buf.writeln('| Severity | ${issue.level.toUpperCase()} |');
    buf.writeln('| Total Occurrences | ${_formatNumber(issue.metrics.totalOccurrences)} |');
    buf.writeln('| Affected Users | ${_formatNumber(issue.metrics.affectedUsers)} |');
    buf.writeln('| First Seen | ${issue.metrics.firstSeen} |');
    buf.writeln('| Last Seen | ${issue.metrics.lastSeen} |');
    buf.writeln('| Rule | `${issue.ruleName}` |');
    buf.writeln('| Error Type | `${issue.errorType}` |');
    buf.writeln('| Children | ${issue.childIssueIds.length} |');
    if (issue.firstSeenRelease != null) {
      buf.writeln('| First Seen Release | `${issue.firstSeenRelease}` |');
    }
    buf.writeln();

    // Stack trace
    if (issue.stackFrames != null && issue.stackFrames!.isNotEmpty) {
      buf.writeln('## Stack Trace');
      buf.writeln();
      buf.writeln('```');
      for (final frame in issue.stackFrames!) {
        final prefix = frame.inApp ? '>' : ' ';
        if (frame.filename.isNotEmpty) {
          buf.writeln('$prefix ${frame.filename}:${frame.lineno} in ${frame.function}');
        } else {
          buf.writeln('$prefix ${frame.function}');
        }
      }
      buf.writeln('```');
      buf.writeln();
    }

    // Sentry links
    if (issue.sentryLinks.isNotEmpty) {
      buf.writeln('## Sentry Links');
      buf.writeln();
      final links = issue.sentryLinks
          .asMap()
          .entries
          .map((e) => '[Issue ${e.key + 1}](${e.value})')
          .join(' - ');
      buf.writeln(links);
      buf.writeln();
    }

    // Smartlook recordings
    if (issue.smartlookUrls.isNotEmpty) {
      buf.writeln('## Smartlook Recordings');
      buf.writeln();
      final links = issue.smartlookUrls
          .asMap()
          .entries
          .map((e) => '[Recording ${e.key + 1}](${e.value})')
          .join(' - ');
      buf.writeln(links);
      buf.writeln();
    }

    // Investigation report
    if (_report != null && _report!.isNotEmpty) {
      buf.writeln('## Investigation Report');
      buf.writeln();
      buf.writeln(_report);
      buf.writeln();
    }

    // Grouping key
    buf.writeln('## Grouping Key');
    buf.writeln();
    buf.writeln('`${issue.groupingKey}`');

    final ok = copyToClipboard(buf.toString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Copied to clipboard' : 'Copy failed'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final levelColor = KahiliColors.levelColor(widget.issue.level);
    final shortTitle = widget.issue.title.split('\n').first;
    final isInvestigating =
        _investigationStatus != null && _investigationStatus!.active;

    return Scaffold(
      backgroundColor: KahiliColors.bg,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: levelColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              widget.issue.id,
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
        onPressed: _shareAsMarkdown,
        backgroundColor: KahiliColors.flame,
        foregroundColor: Colors.black,
        child: const Icon(Icons.copy_all),
      ),
      body: CopyableSelectionArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Title block ────────────────────────────────────────────
          _titleBlock(shortTitle, levelColor),
          const SizedBox(height: 16),

          // ── Metrics ────────────────────────────────────────────────
          _metricsRow(),
          const SizedBox(height: 16),

          // ── Timeline ───────────────────────────────────────────────
          sectionHeader('Timeline'),
          darkCard(
            child: Column(
              children: [
                timelineRow('First seen', _formatDate(widget.issue.metrics.firstSeen), KahiliColors.emerald),
                if (widget.issue.firstSeenRelease != null) ...[
                  kahiliDivider(),
                  timelineRow('First version', widget.issue.firstSeenRelease!, KahiliColors.cyan),
                ],
                kahiliDivider(),
                timelineRow('Last seen', _formatDate(widget.issue.metrics.lastSeen), KahiliColors.flame),
                kahiliDivider(),
                timelineRow('Created', _formatDate(widget.issue.createdAt), KahiliColors.textTertiary),
                kahiliDivider(),
                timelineRow('Updated', _formatDate(widget.issue.updatedAt), KahiliColors.textTertiary),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Stack trace ────────────────────────────────────────────
          if (widget.issue.stackFrames != null && widget.issue.stackFrames!.isNotEmpty) ...[
            sectionHeader('Stack Trace'),
            StackTraceBlock(frames: widget.issue.stackFrames!),
            const SizedBox(height: 16),
          ],

          // ── Rule section ────────────────────────────────────────────
          Builder(builder: (_) {
            try {
              return _ruleSection();
            } catch (e) {
              return Text('Rule error: $e', style: const TextStyle(color: Colors.red, fontSize: 12));
            }
          }),
          const SizedBox(height: 16),

          // ── Investigation section ──────────────────────────────────
          InvestigationPanel(
            reportLoading: _reportLoading,
            isInvestigating: isInvestigating,
            report: _report,
            investigationStatus: _investigationStatus,
            onInvestigate: _openInvestigateDialog,
          ),
          const SizedBox(height: 16),

          // ── Child issues (selectable) ─────────────────────────────
          if (widget.issue.sentryLinks.isNotEmpty) ...[
            ChildIssuesSection(
              key: _childIssuesKey,
              sentryLinks: widget.issue.sentryLinks,
              childIssueIds: widget.issue.childIssueIds,
              childStatuses: widget.issue.childStatuses,
              onArchivePressed: _onArchivePressed,
            ),
            const SizedBox(height: 16),
          ],

          // ── Smartlook sessions ─────────────────────────────────────
          if (widget.issue.smartlookUrls.isNotEmpty) ...[
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
                  iconColor: KahiliColors.textTertiary,
                  title: Row(
                    children: [
                      const Icon(Icons.play_circle_outline, size: 16, color: KahiliColors.cyanMuted),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.issue.smartlookUrls.length} Smartlook session${widget.issue.smartlookUrls.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 13, color: KahiliColors.textSecondary),
                      ),
                    ],
                  ),
                  children: [
                    const Divider(height: 1, color: KahiliColors.border),
                    for (int i = 0; i < widget.issue.smartlookUrls.length; i++) ...[
                      if (i > 0) kahiliDivider(),
                      linkRow(context, widget.issue.smartlookUrls[i], Icons.play_circle_outline),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Grouping key ───────────────────────────────────────────
          sectionHeader('Grouping Key'),
          GestureDetector(
            onTap: () => _copy(context, widget.issue.groupingKey),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: KahiliColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: KahiliColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.issue.groupingKey,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: KahiliColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy_rounded, size: 16, color: KahiliColors.textTertiary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      )),
    );
  }

  // ── Archive handler ────────────────────────────────────────────────

  Future<void> _onArchivePressed(List<String> selectedIds, List<String> selectedLinks) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ArchiveDialog(
          issueIds: selectedIds,
          sentryLinks: selectedLinks,
          ruleName: widget.issue.ruleName,
          ruleDescription: _originalRuleDescription,
        ),
      ),
    );

    if (result != null && mounted) {
      final allOk = result['ok'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(allOk
              ? 'Archived ${selectedIds.length} issue${selectedIds.length == 1 ? '' : 's'}'
              : 'Some issues failed to archive'),
          backgroundColor: allOk ? KahiliColors.emerald : KahiliColors.error,
        ),
      );
      // Trigger rebuild of child issues section by updating statuses
      setState(() {
        for (int i = 0; i < widget.issue.sentryLinks.length; i++) {
          if (selectedLinks.contains(widget.issue.sentryLinks[i]) && i < widget.issue.childStatuses.length) {
            widget.issue.childStatuses[i] = 'ignored';
          }
        }
      });
    }
  }

  // ── Rule section ─────────────────────────────────────────────────

  Widget _ruleSection() {
    final hasChanged = !_ruleLoading && _ruleController.text.trim() != _originalRuleDescription;
    final isGenerating = _regenerating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeader('Rule'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: KahiliColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KahiliColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rule name badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0x14009DB2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x28009DB2)),
                ),
                child: Text(
                  widget.issue.ruleName,
                  style: const TextStyle(fontSize: 11, color: KahiliColors.cyan, fontWeight: FontWeight.w600),
                ),
              ),
              // Implementation logic (readonly)
              if (_ruleLogic.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF08080E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: KahiliColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'IMPLEMENTATION',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: KahiliColors.textTertiary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _ruleLogic,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: KahiliColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              // Editable description
              TextField(
                controller: _ruleController,
                maxLines: 3,
                minLines: 1,
                enabled: !isGenerating && !_ruleLoading,
                style: const TextStyle(fontSize: 13, color: KahiliColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Rule description / prompt...',
                  hintStyle: const TextStyle(color: KahiliColors.textTertiary),
                  filled: true,
                  fillColor: const Color(0xFF08080E),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: KahiliColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: KahiliColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: KahiliColors.flame),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: KahiliColors.border),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),

              // Generation status
              if (isGenerating && _regenStatus != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF08080E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: KahiliColors.gold),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _regenStatus?.lastStatus?.trim() ?? 'Generating...',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: KahiliColors.textTertiary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // Regenerate button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isGenerating ? null : _regenerateRule,
                  icon: isGenerating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.autorenew, size: 18),
                  label: Text(
                    isGenerating ? 'Regenerating...' : (hasChanged ? 'Regenerate Rule' : 'Regenerate'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: hasChanged ? KahiliColors.flame : const Color(0xFF1C1C2E),
                    foregroundColor: hasChanged ? Colors.black : KahiliColors.textSecondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Remaining private widgets ──────────────────────────────────────

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
                  color: KahiliColors.cyan.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KahiliColors.cyan.withAlpha(40)),
                ),
                child: Text(
                  widget.issue.ruleName,
                  style: const TextStyle(fontSize: 10, color: KahiliColors.cyan, fontWeight: FontWeight.w600),
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
          if (widget.issue.title.contains('\n')) ...[
            const SizedBox(height: 6),
            Text(
              widget.issue.title.split('\n').skip(1).join('\n'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KahiliColors.textTertiary,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
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
            _formatCount(widget.issue.metrics.totalOccurrences), 'Events'),
        const SizedBox(width: 8),
        _metricTile(Icons.people, KahiliColors.cyanMuted,
            _formatCount(widget.issue.metrics.affectedUsers), 'Users'),
        const SizedBox(width: 8),
        _metricTile(Icons.account_tree, KahiliColors.emerald,
            widget.issue.childIssueIds.length.toString(), 'Children'),
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
}
