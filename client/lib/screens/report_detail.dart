import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_client.dart';
import '../theme/kahili_theme.dart';
import '../utils/web_download.dart';

class ReportDetail extends StatefulWidget {
  final String date;

  const ReportDetail({super.key, required this.date});

  @override
  State<ReportDetail> createState() => _ReportDetailState();
}

class _ReportDetailState extends State<ReportDetail> {
  String? _rawMarkdown;
  List<_ReportRow> _rows = [];
  int _resolvedCount = 0;
  int _archivedCount = 0;
  String _generatedAt = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final md = await ApiClient.getDailyReport(widget.date);
      if (!mounted) return;
      if (md != null) {
        _rawMarkdown = md;
        _parse(md);
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parse(String md) {
    final lines = md.split('\n');
    final rows = <_ReportRow>[];

    for (final line in lines) {
      if (line.startsWith('Generated:')) {
        _generatedAt = line.replaceFirst('Generated: ', '').trim();
      }
      if (line.startsWith('Resolved:')) {
        final m = RegExp(r'Resolved: (\d+) \| Archived: (\d+)').firstMatch(line);
        if (m != null) {
          _resolvedCount = int.tryParse(m.group(1) ?? '') ?? 0;
          _archivedCount = int.tryParse(m.group(2) ?? '') ?? 0;
        }
      }
      if (line.startsWith('| #') || line.startsWith('|---') || !line.startsWith('|')) continue;

      final cells = line.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
      if (cells.length >= 5) {
        final issueCell = cells[1];
        String issueId = '';
        String issueUrl = '';
        String issueTitle = '';
        final linkMatch = RegExp(r'\[([^\]]+)\]\(([^)]+)\)(.*)').firstMatch(issueCell);
        if (linkMatch != null) {
          issueId = linkMatch.group(1) ?? '';
          issueUrl = linkMatch.group(2) ?? '';
          issueTitle = (linkMatch.group(3) ?? '').replaceFirst(RegExp(r'^:\s*'), '').trim();
        } else {
          issueTitle = issueCell;
        }

        String jiraUrl = '';
        String jiraId = '';
        if (cells.length >= 6) {
          final jiraCell = cells[5];
          final jiraMatch = RegExp(r'\[([^\]]+)\]\(([^)]+)\)').firstMatch(jiraCell);
          if (jiraMatch != null) {
            jiraId = jiraMatch.group(1) ?? '';
            jiraUrl = jiraMatch.group(2) ?? '';
          }
        }

        rows.add(_ReportRow(
          issueId: issueId,
          issueUrl: issueUrl,
          issueTitle: issueTitle,
          action: cells[2],
          actor: cells[3],
          conditions: cells[4],
          jiraId: jiraId,
          jiraUrl: jiraUrl,
        ));
      }
    }

    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _share() {
    if (_rawMarkdown == null) return;
    downloadTextFile(_rawMarkdown!, 'report-${widget.date}.md');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KahiliColors.bg,
      appBar: AppBar(
        title: Text('Report ${widget.date}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: KahiliColors.border),
        ),
      ),
      floatingActionButton: _rawMarkdown != null
          ? FloatingActionButton(
              onPressed: _share,
              backgroundColor: KahiliColors.flame,
              foregroundColor: Colors.black,
              child: const Icon(Icons.download),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('No data', style: TextStyle(color: KahiliColors.textTertiary)))
              : SelectionArea(child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    // Summary stats
                    _statsRow(),
                    const SizedBox(height: 4),
                    if (_generatedAt.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 12),
                        child: Text(
                          'Updated: ${_formatTimestamp(_generatedAt)}',
                          style: const TextStyle(fontSize: 11, color: KahiliColors.textTertiary),
                        ),
                      ),
                    // Issue rows
                    for (final row in _rows) _buildRow(row),
                    const SizedBox(height: 80), // space for FAB
                  ],
                )),
    );
  }

  Widget _statsRow() {
    return Row(
      children: [
        _statTile('Archived', _archivedCount, KahiliColors.gold),
        const SizedBox(width: 8),
        _statTile('Resolved', _resolvedCount, KahiliColors.emerald),
        const SizedBox(width: 8),
        _statTile('Total', _archivedCount + _resolvedCount, KahiliColors.textPrimary),
      ],
    );
  }

  Widget _statTile(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: KahiliColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KahiliColors.border),
        ),
        child: Column(
          children: [
            Text(
              value.toString(),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: KahiliColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(_ReportRow row) {
    final isArchived = row.action.toLowerCase().contains('archived');
    final actionColor = isArchived ? KahiliColors.gold : KahiliColors.emerald;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KahiliColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KahiliColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: issue ID + action badge
          Row(
            children: [
              if (row.issueUrl.isNotEmpty)
                GestureDetector(
                  onTap: () => launchUrl(Uri.parse(row.issueUrl), mode: LaunchMode.externalApplication),
                  child: Text(
                    row.issueId,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: KahiliColors.cyan,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                )
              else
                Text(row.issueId, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: KahiliColors.textSecondary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: actionColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: actionColor.withAlpha(60)),
                ),
                child: Text(
                  row.action,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: actionColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Title
          Text(
            row.issueTitle,
            style: const TextStyle(fontSize: 13, color: KahiliColors.textPrimary, height: 1.3),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          // Actor + conditions + jira
          if (row.actor.isNotEmpty && row.actor != '—')
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 14, color: KahiliColors.textTertiary),
                  const SizedBox(width: 6),
                  Text(row.actor, style: const TextStyle(fontSize: 12, color: KahiliColors.textSecondary)),
                ],
              ),
            ),

          if (row.conditions.isNotEmpty && row.conditions != '—')
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 14, color: KahiliColors.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      row.conditions,
                      style: const TextStyle(fontSize: 12, color: KahiliColors.textTertiary),
                    ),
                  ),
                ],
              ),
            ),

          if (row.jiraId.isNotEmpty)
            GestureDetector(
              onTap: () => launchUrl(Uri.parse(row.jiraUrl), mode: LaunchMode.externalApplication),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 14, color: KahiliColors.cyan),
                  const SizedBox(width: 6),
                  Text(row.jiraId, style: const TextStyle(fontSize: 12, color: KahiliColors.cyan)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ReportRow {
  final String issueId;
  final String issueUrl;
  final String issueTitle;
  final String action;
  final String actor;
  final String conditions;
  final String jiraId;
  final String jiraUrl;

  _ReportRow({
    required this.issueId,
    required this.issueUrl,
    required this.issueTitle,
    required this.action,
    required this.actor,
    required this.conditions,
    required this.jiraId,
    required this.jiraUrl,
  });
}
