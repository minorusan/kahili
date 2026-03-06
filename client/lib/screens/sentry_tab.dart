import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';
import '../models/mother_issue.dart';
import '../theme/kahili_theme.dart';
import 'widgets/shared_widgets.dart';
import 'filter_page.dart';
import 'mother_issue_detail.dart';
import 'widgets/issue_card.dart';

class SentryTab extends StatefulWidget {
  const SentryTab({super.key});

  @override
  State<SentryTab> createState() => _SentryTabState();
}

class _SentryTabState extends State<SentryTab> {
  late Future<List<MotherIssue>> _issuesFuture;
  String? _activeInvestigationIssueId;
  Set<String> _investigatedIds = {};

  String _searchText = '';
  FilterSettings _filterSettings = const FilterSettings();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _issuesFuture = ApiClient.getMotherIssues();
    _checkStatuses();
    _loadFilterSettings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFilterSettings() async {
    final settings = await FilterSettings.load();
    if (mounted) setState(() => _filterSettings = settings);
  }

  void _refresh() {
    setState(() {
      _issuesFuture = ApiClient.getMotherIssues();
    });
    _checkStatuses();
  }

  Future<void> _checkStatuses() async {
    await Future.wait([_checkInvestigation(), _checkInvestigated()]);
  }

  Future<void> _checkInvestigation() async {
    try {
      final status = await ApiClient.getInvestigationStatus();
      setState(() {
        _activeInvestigationIssueId = status.active ? status.motherIssueId : null;
      });
    } catch (_) {}
  }

  Future<void> _checkInvestigated() async {
    try {
      final ids = await ApiClient.getInvestigatedIssueIds();
      setState(() => _investigatedIds = ids);
    } catch (_) {}
  }

  String _timeAgo(String isoDate) {
    if (isoDate.isEmpty) return '';
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return isoDate;
    final diff = DateTime.now().toUtc().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  /// Serialize all fields of an issue into one string for filter matching.
  String _serializeIssue(MotherIssue issue) {
    final buf = StringBuffer();
    buf.writeln(issue.id);
    buf.writeln(issue.title);
    buf.writeln(issue.errorType);
    buf.writeln(issue.level);
    buf.writeln(issue.ruleName);
    buf.writeln(issue.groupingKey);
    for (final link in issue.sentryLinks) {
      buf.writeln(link);
    }
    for (final link in issue.smartlookUrls) {
      buf.writeln(link);
    }
    if (issue.stackFrames != null) {
      for (final frame in issue.stackFrames!) {
        buf.writeln('${frame.filename}:${frame.lineno} ${frame.function}');
      }
    }
    return buf.toString().toLowerCase();
  }

  bool _matchesFilter(MotherIssue issue) {
    if (_filterSettings.filterStrings.isEmpty) return false;
    final blob = _serializeIssue(issue);
    return _filterSettings.filterStrings.any(
      (f) => blob.contains(f.toLowerCase()),
    );
  }

  /// Apply the full pipeline: search → sort → partition (filter-matched first).
  List<DisplayIssue> _applyPipeline(List<MotherIssue> raw) {
    // 1. Text search
    var filtered = raw;
    if (_searchText.isNotEmpty) {
      final query = _searchText.toLowerCase();
      filtered = raw.where((i) => i.title.toLowerCase().contains(query)).toList();
    }

    // 2. Sort — archived mother issues always sink to the bottom
    filtered.sort((a, b) {
      // Archived issues go to the bottom regardless of sort settings
      if (a.allChildrenArchived != b.allChildrenArchived) {
        return a.allChildrenArchived ? 1 : -1;
      }
      int cmp;
      if (_filterSettings.sortField == 'affectedUsers') {
        cmp = a.metrics.affectedUsers.compareTo(b.metrics.affectedUsers);
      } else {
        cmp = a.metrics.lastSeen.compareTo(b.metrics.lastSeen);
      }
      return _filterSettings.sortAscending ? cmp : -cmp;
    });

    // 3. Partition: filter-matched issues first
    final hasFilters = _filterSettings.filterStrings.isNotEmpty;
    if (!hasFilters) {
      return filtered.map((i) => DisplayIssue(issue: i, matchesFilter: false)).toList();
    }

    final matching = <DisplayIssue>[];
    final rest = <DisplayIssue>[];
    for (final issue in filtered) {
      if (_matchesFilter(issue)) {
        matching.add(DisplayIssue(issue: issue, matchesFilter: true));
      } else {
        rest.add(DisplayIssue(issue: issue, matchesFilter: false));
      }
    }
    return [...matching, ...rest];
  }

  Future<void> _openFilterPage() async {
    final result = await Navigator.of(context).push<FilterSettings>(
      MaterialPageRoute(
        builder: (_) => const FilterPage(),
      ),
    );
    if (mounted) {
      if (result != null) {
        setState(() => _filterSettings = result);
      } else {
        // Fallback: reload from prefs in case pop didn't carry the result
        _loadFilterSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MotherIssue>>(
      future: _issuesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: KahiliColors.error),
                  const SizedBox(height: 12),
                  const Text('Failed to load issues',
                      style: TextStyle(color: KahiliColors.textPrimary, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('${snapshot.error}',
                      style: const TextStyle(color: KahiliColors.textTertiary, fontSize: 12),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final issues = snapshot.data ?? [];

        if (issues.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 48, color: KahiliColors.emerald),
                SizedBox(height: 12),
                Text('No mother issues', style: TextStyle(color: KahiliColors.textSecondary)),
              ],
            ),
          );
        }

        final displayIssues = _applyPipeline(issues);

        return RefreshIndicator(
          color: KahiliColors.flame,
          backgroundColor: KahiliColors.surfaceLight,
          onRefresh: () async {
            _refresh();
            await _issuesFuture;
          },
          child: CopyableSelectionArea(child: Column(
            children: [
              // ── Search bar + filter button ──────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: KahiliColors.surfaceLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: KahiliColors.border),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _searchText = v),
                          style: const TextStyle(fontSize: 14, color: KahiliColors.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Search issues...',
                            hintStyle: TextStyle(color: KahiliColors.textTertiary, fontSize: 14),
                            prefixIcon: Icon(Icons.search, size: 20, color: KahiliColors.textTertiary),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Material(
                        color: _filterSettings.filterStrings.isNotEmpty
                            ? KahiliColors.flame.withAlpha(20)
                            : KahiliColors.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _openFilterPage,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _filterSettings.filterStrings.isNotEmpty
                                    ? KahiliColors.flame.withAlpha(60)
                                    : KahiliColors.border,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.tune,
                              size: 20,
                              color: _filterSettings.filterStrings.isNotEmpty
                                  ? KahiliColors.flame
                                  : KahiliColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Issue list ─────────────────────────────
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: displayIssues.length,
                  itemBuilder: (context, index) {
                    final di = displayIssues[index];
                    final issue = di.issue;
                    final isInvestigating = _activeInvestigationIssueId == issue.id;
                    final isInvestigated = _investigatedIds.contains(issue.id);
                    return IssueCard(
                      issue: issue,
                      isInvestigating: isInvestigating,
                      isInvestigated: isInvestigated,
                      isArchived: issue.allChildrenArchived,
                      matchesFilter: di.matchesFilter,
                      timeAgo: _timeAgo(issue.metrics.lastSeen),
                      formatCount: _formatCount,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MotherIssueDetail(issue: issue),
                          ),
                        );
                        // Refresh statuses when returning
                        _checkStatuses();
                      },
                    );
                  },
                ),
              ),
            ],
          )),
        );
      },
    );
  }
}
