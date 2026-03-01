import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/mother_issue.dart';
import '../models/sentry_issue.dart';
import '../theme/kahili_theme.dart';
import 'incoming_issue_detail.dart';

class IncomingTab extends StatefulWidget {
  const IncomingTab({super.key});

  @override
  State<IncomingTab> createState() => IncomingTabState();
}

class IncomingTabState extends State<IncomingTab> {
  List<SentryIssue>? _orphans;
  bool _loading = true;
  String? _error;
  String _searchText = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiClient.getIssues(),
        ApiClient.getMotherIssues(),
      ]);
      final allIssues = results[0] as List<SentryIssue>;
      final mothers = results[1] as List<MotherIssue>;

      final groupedIds = <String>{};
      for (final m in mothers) {
        groupedIds.addAll(m.childIssueIds);
      }

      final orphans = allIssues.where((i) => !groupedIds.contains(i.id)).toList();
      orphans.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

      if (mounted) setState(() { _orphans = orphans; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  void refresh() => _load();

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

  String _formatCount(String n) {
    final v = int.tryParse(n) ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return n;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
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
              Text(_error!,
                  style: const TextStyle(color: KahiliColors.textTertiary, fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final orphans = _orphans ?? [];

    if (orphans.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: KahiliColors.emerald),
            SizedBox(height: 12),
            Text('All issues are grouped', style: TextStyle(color: KahiliColors.textSecondary)),
          ],
        ),
      );
    }

    // Apply search filter
    var displayIssues = orphans;
    if (_searchText.isNotEmpty) {
      final query = _searchText.toLowerCase();
      displayIssues = orphans.where((i) => i.title.toLowerCase().contains(query)).toList();
    }

    return RefreshIndicator(
      color: KahiliColors.flame,
      backgroundColor: KahiliColors.surfaceLight,
      onRefresh: () async => _load(),
      child: SelectionArea(child: Column(
        children: [
          // ── Search bar ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
                  hintText: 'Search incoming...',
                  hintStyle: TextStyle(color: KahiliColors.textTertiary, fontSize: 14),
                  prefixIcon: Icon(Icons.search, size: 20, color: KahiliColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          // ── Issue list ─────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              itemCount: displayIssues.length,
              itemBuilder: (context, index) {
                final issue = displayIssues[index];
                return _IncomingIssueCard(
                  issue: issue,
                  timeAgo: _timeAgo(issue.lastSeen),
                  formatCount: _formatCount,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => IncomingIssueDetail(issue: issue),
                      ),
                    );
                    _load();
                  },
                );
              },
            ),
          ),
        ],
      )),
    );
  }
}

class _IncomingIssueCard extends StatelessWidget {
  final SentryIssue issue;
  final String timeAgo;
  final String Function(String) formatCount;
  final VoidCallback onTap;

  const _IncomingIssueCard({
    required this.issue,
    required this.timeAgo,
    required this.formatCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final levelColor = KahiliColors.levelColor(issue.level);
    final shortTitle = issue.title.split('\n').first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
                // Title
                Text(
                  shortTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KahiliColors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),

                // Bottom row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: KahiliColors.textTertiary.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: KahiliColors.textTertiary.withAlpha(40)),
                      ),
                      child: const Text(
                        'NO RULE',
                        style: TextStyle(
                          fontSize: 10,
                          color: KahiliColors.textTertiary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _stat(Icons.local_fire_department, formatCount(issue.count)),
                    const SizedBox(width: 10),
                    _stat(Icons.people_outline, '${issue.userCount}'),
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
