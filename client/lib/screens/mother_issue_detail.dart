import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_client.dart';
import '../models/mother_issue.dart';
import '../theme/kahili_theme.dart';
import '../utils/web_download.dart';
import 'investigate_dialog.dart';
import 'archive_dialog.dart';

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

  // Archive selection
  final Set<int> _selectedChildIndices = {};

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
    _ruleController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadReport(), _pollInvestigation(), _loadRuleDescription()]);
    _startPollingIfNeeded();
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
      body: SelectionArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Title block ────────────────────────────────────────────
          _titleBlock(shortTitle, levelColor),
          const SizedBox(height: 16),

          // ── Metrics ────────────────────────────────────────────────
          _metricsRow(),
          const SizedBox(height: 16),

          // ── Timeline ───────────────────────────────────────────────
          _section('Timeline'),
          _darkCard(
            child: Column(
              children: [
                _timelineRow('First seen', _formatDate(widget.issue.metrics.firstSeen), KahiliColors.emerald),
                if (widget.issue.firstSeenRelease != null) ...[
                  _divider(),
                  _timelineRow('First version', widget.issue.firstSeenRelease!, KahiliColors.cyan),
                ],
                _divider(),
                _timelineRow('Last seen', _formatDate(widget.issue.metrics.lastSeen), KahiliColors.flame),
                _divider(),
                _timelineRow('Created', _formatDate(widget.issue.createdAt), KahiliColors.textTertiary),
                _divider(),
                _timelineRow('Updated', _formatDate(widget.issue.updatedAt), KahiliColors.textTertiary),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Stack trace ────────────────────────────────────────────
          if (widget.issue.stackFrames != null && widget.issue.stackFrames!.isNotEmpty) ...[
            _section('Stack Trace'),
            _stackTraceBlock(),
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
          _investigationSection(isInvestigating),
          const SizedBox(height: 16),

          // ── Child issues (selectable) ─────────────────────────────
          if (widget.issue.sentryLinks.isNotEmpty) ...[
            _childIssuesSection(),
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
                      if (i > 0) _divider(),
                      _linkRow(context, widget.issue.smartlookUrls[i], Icons.play_circle_outline),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Grouping key ───────────────────────────────────────────
          _section('Grouping Key'),
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

  // ── Child issues section ────────────────────────────────────────

  Widget _childIssuesSection() {
    final issue = widget.issue;
    final unresolvedCount = issue.childStatuses
        .where((s) => s == 'unresolved')
        .length;
    final hasSelection = _selectedChildIndices.isNotEmpty;

    // Split into unresolved and resolved/archived
    final unresolvedIndices = <int>[];
    final archivedIndices = <int>[];
    for (int i = 0; i < issue.sentryLinks.length; i++) {
      if (i < issue.childStatuses.length && issue.childStatuses[i] != 'unresolved') {
        archivedIndices.add(i);
      } else {
        unresolvedIndices.add(i);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with select-all for unresolved
        Row(
          children: [
            Expanded(child: _section('Child Issues')),
            if (unresolvedCount > 0)
              GestureDetector(
                onTap: () {
                  setState(() {
                    final allUnresolved = unresolvedIndices.toSet();
                    if (_selectedChildIndices.containsAll(allUnresolved)) {
                      _selectedChildIndices.clear();
                    } else {
                      _selectedChildIndices.addAll(allUnresolved);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 4),
                  child: Text(
                    hasSelection ? 'Deselect all' : 'Select all unresolved',
                    style: const TextStyle(
                      fontSize: 12,
                      color: KahiliColors.flame,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),

        // Unresolved issues
        if (unresolvedIndices.isNotEmpty)
          _darkCard(
            child: Column(
              children: [
                for (int j = 0; j < unresolvedIndices.length; j++) ...[
                  if (j > 0) _divider(),
                  _unresolvedChildRow(unresolvedIndices[j]),
                ],
              ],
            ),
          ),

        // Resolved/archived issues in foldout
        if (archivedIndices.isNotEmpty) ...[
          const SizedBox(height: 8),
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
                    const Icon(Icons.archive_outlined, size: 16, color: KahiliColors.textTertiary),
                    const SizedBox(width: 8),
                    Text(
                      '${archivedIndices.length} resolved / archived',
                      style: const TextStyle(fontSize: 13, color: KahiliColors.textTertiary),
                    ),
                  ],
                ),
                children: [
                  const Divider(height: 1, color: KahiliColors.border),
                  for (int j = 0; j < archivedIndices.length; j++) ...[
                    if (j > 0) _divider(),
                    _archivedChildRow(archivedIndices[j]),
                  ],
                ],
              ),
            ),
          ),
        ],

        // Archive button
        if (hasSelection) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _openArchiveDialog,
              icon: const Icon(Icons.archive, size: 18),
              label: Text(
                'Archive ${_selectedChildIndices.length} issue${_selectedChildIndices.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: KahiliColors.flame,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _unresolvedChildRow(int index) {
    final url = widget.issue.sentryLinks[index];
    final isSelected = _selectedChildIndices.contains(index);
    final issueId = index < widget.issue.childIssueIds.length
        ? widget.issue.childIssueIds[index]
        : '';
    final shortId = url.split('/').where((s) => s.isNotEmpty).lastOrNull ?? issueId;

    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        color: isSelected ? KahiliColors.flame.withAlpha(12) : null,
        child: Row(
          children: [
            // Checkbox — precise tap target
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                if (isSelected) {
                  _selectedChildIndices.remove(index);
                } else {
                  _selectedChildIndices.add(index);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? KahiliColors.flame : KahiliColors.textTertiary,
                      width: isSelected ? 2 : 1.5,
                    ),
                    color: isSelected ? KahiliColors.flame.withAlpha(25) : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 12, color: KahiliColors.flame)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Issue link
            Expanded(
              child: Text(
                shortId,
                style: const TextStyle(
                  fontSize: 12,
                  color: KahiliColors.cyan,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.open_in_new, size: 14, color: KahiliColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _archivedChildRow(int index) {
    final url = widget.issue.sentryLinks[index];
    final issueId = index < widget.issue.childIssueIds.length
        ? widget.issue.childIssueIds[index]
        : '';
    final shortId = url.split('/').where((s) => s.isNotEmpty).lastOrNull ?? issueId;
    final status = index < widget.issue.childStatuses.length
        ? widget.issue.childStatuses[index]
        : 'archived';

    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                shortId,
                style: const TextStyle(
                  fontSize: 12,
                  color: KahiliColors.textTertiary,
                  fontFamily: 'monospace',
                  decoration: TextDecoration.lineThrough,
                  decorationColor: KahiliColors.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: KahiliColors.textTertiary.withAlpha(20),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                status,
                style: const TextStyle(fontSize: 10, color: KahiliColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openArchiveDialog() async {
    final selectedIds = _selectedChildIndices
        .where((i) => i < widget.issue.childIssueIds.length)
        .map((i) => widget.issue.childIssueIds[i])
        .toList();
    final selectedLinks = _selectedChildIndices
        .where((i) => i < widget.issue.sentryLinks.length)
        .map((i) => widget.issue.sentryLinks[i])
        .toList();

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
      // Clear selection and mark as archived locally
      setState(() {
        for (final idx in _selectedChildIndices) {
          if (idx < widget.issue.childStatuses.length) {
            widget.issue.childStatuses[idx] = 'ignored';
          }
        }
        _selectedChildIndices.clear();
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
        _section('Rule'),
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

  String? _extractTldr(String report) {
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

  // ── Investigation section ─────────────────────────────────────────

  Widget _investigationSection(bool isInvestigating) {
    // Loading state
    if (_reportLoading) {
      return _darkCard(
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
    if (_report != null && _report!.isNotEmpty) {
      // Extract TLDR section for collapsed preview
      final tldr = _extractTldr(_report!);

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
              onPressed: _openInvestigateDialog,
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
        onPressed: _openInvestigateDialog,
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
    final elapsed = _investigationStatus!.startedAt != null
        ? DateTime.now()
            .toUtc()
            .difference(DateTime.parse(_investigationStatus!.startedAt!))
        : null;
    final elapsedStr = elapsed != null
        ? '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s'
        : '';

    // Show last few lines of the report as live preview
    final lastReport = _investigationStatus!.lastReport ?? '';
    final previewLines = lastReport.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final preview = previewLines.length > 6
        ? previewLines.sublist(previewLines.length - 6).join('\n')
        : previewLines.join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Investigation In Progress'),
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
              if (_investigationStatus!.branch != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.commit, size: 14, color: KahiliColors.textTertiary),
                      const SizedBox(width: 6),
                      Text(
                        _investigationStatus!.branch!,
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
        data: _report!,
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

  // ── Shared widgets ────────────────────────────────────────────────

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

  Widget _stackTraceBlock() {
    final frames = widget.issue.stackFrames!;
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

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KahiliColors.textSecondary, letterSpacing: 0.3)),
    );
  }

  Widget _darkCard({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: KahiliColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KahiliColors.border),
      ),
      child: child,
    );
  }

  Widget _divider() => const Divider(height: 1, color: KahiliColors.border);

  Widget _timelineRow(String label, String value, Color dotColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, color: KahiliColors.textTertiary))),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, color: KahiliColors.textPrimary, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(BuildContext context, String url, IconData icon) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      onLongPress: () => _copy(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: KahiliColors.cyanMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(url, style: const TextStyle(fontSize: 12, color: KahiliColors.cyan, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _copy(context, url),
              child: const Icon(Icons.copy_rounded, size: 14, color: KahiliColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _childLinkRow(BuildContext context, String url, {required bool isArchived}) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      onLongPress: () => _copy(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              isArchived ? Icons.archive_outlined : Icons.open_in_new,
              size: 16,
              color: isArchived ? KahiliColors.textTertiary : KahiliColors.cyanMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                url,
                style: TextStyle(
                  fontSize: 12,
                  color: isArchived ? KahiliColors.textTertiary : KahiliColors.cyan,
                  fontFamily: 'monospace',
                  decoration: isArchived ? TextDecoration.lineThrough : null,
                  decorationColor: KahiliColors.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _copy(context, url),
              child: const Icon(Icons.copy_rounded, size: 14, color: KahiliColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
