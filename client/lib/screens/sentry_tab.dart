import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/mother_issue.dart';
import '../theme/kahili_theme.dart';
import 'filter_page.dart';
import 'mother_issue_detail.dart';

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
  List<_DisplayIssue> _applyPipeline(List<MotherIssue> raw) {
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
      return filtered.map((i) => _DisplayIssue(issue: i, matchesFilter: false)).toList();
    }

    final matching = <_DisplayIssue>[];
    final rest = <_DisplayIssue>[];
    for (final issue in filtered) {
      if (_matchesFilter(issue)) {
        matching.add(_DisplayIssue(issue: issue, matchesFilter: true));
      } else {
        rest.add(_DisplayIssue(issue: issue, matchesFilter: false));
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
          child: SelectionArea(child: Column(
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
                    return _IssueCard(
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

class _DisplayIssue {
  final MotherIssue issue;
  final bool matchesFilter;

  _DisplayIssue({required this.issue, required this.matchesFilter});
}

class _IssueCard extends StatelessWidget {
  final MotherIssue issue;
  final bool isInvestigating;
  final bool isInvestigated;
  final bool isArchived;
  final bool matchesFilter;
  final String timeAgo;
  final String Function(int) formatCount;
  final VoidCallback onTap;

  const _IssueCard({
    required this.issue,
    required this.isInvestigating,
    required this.isInvestigated,
    required this.isArchived,
    required this.matchesFilter,
    required this.timeAgo,
    required this.formatCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final levelColor = isArchived
        ? KahiliColors.textTertiary.withAlpha(80)
        : KahiliColors.levelColor(issue.level);
    final shortTitle = issue.title.split('\n').first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: isArchived ? 0.45 : 1.0,
        child: Material(
        color: KahiliColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: KahiliColors.flame.withAlpha(20),
          highlightColor: KahiliColors.flame.withAlpha(10),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: levelColor, width: 3),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row with optional investigation indicator + filter icon
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        shortTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isArchived
                              ? KahiliColors.textTertiary
                              : KahiliColors.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ),
                    if (matchesFilter) ...[
                      const SizedBox(width: 6),
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.filter_alt, size: 14, color: KahiliColors.flame),
                      ),
                    ],
                    if (isInvestigating) ...[
                      const SizedBox(width: 8),
                      _InvestigatingBadge(),
                    ] else if (isInvestigated) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: KahiliColors.emerald.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: KahiliColors.emerald.withAlpha(50)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, size: 10, color: KahiliColors.emerald),
                            SizedBox(width: 4),
                            Text(
                              'INVESTIGATED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: KahiliColors.emerald,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),

                // Bottom row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: KahiliColors.cyan.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: KahiliColors.cyan.withAlpha(40)),
                      ),
                      child: Text(
                        issue.ruleName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: KahiliColors.cyan,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _stat(Icons.local_fire_department, formatCount(issue.metrics.totalOccurrences)),
                    const SizedBox(width: 10),
                    _stat(Icons.people_outline, formatCount(issue.metrics.affectedUsers)),
                    if (issue.childIssueIds.length > 1) ...[
                      const SizedBox(width: 10),
                      _stat(Icons.account_tree_outlined, '${issue.childIssueIds.length}'),
                    ],
                    const Spacer(),
                    Text(
                      timeAgo,
                      style: const TextStyle(fontSize: 11, color: KahiliColors.textTertiary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _stat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: KahiliColors.textTertiary),
        const SizedBox(width: 3),
        Text(value, style: const TextStyle(fontSize: 12, color: KahiliColors.textSecondary)),
      ],
    );
  }
}

class _InvestigatingBadge extends StatefulWidget {
  @override
  State<_InvestigatingBadge> createState() => _InvestigatingBadgeState();
}

class _InvestigatingBadgeState extends State<_InvestigatingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: KahiliColors.gold.withAlpha(15 + (_controller.value * 20).toInt()),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: KahiliColors.gold.withAlpha(40 + (_controller.value * 40).toInt()),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: KahiliColors.gold,
                  value: null,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'INVESTIGATING',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: KahiliColors.gold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
