import 'package:flutter/material.dart';
import '../../models/mother_issue.dart';
import '../../theme/kahili_theme.dart';
import 'investigating_badge.dart';

class DisplayIssue {
  final MotherIssue issue;
  final bool matchesFilter;

  DisplayIssue({required this.issue, required this.matchesFilter});
}

class IssueCard extends StatelessWidget {
  final MotherIssue issue;
  final bool isInvestigating;
  final bool isInvestigated;
  final bool isArchived;
  final bool matchesFilter;
  final String timeAgo;
  final String Function(int) formatCount;
  final VoidCallback onTap;

  const IssueCard({
    super.key,
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
                      InvestigatingBadge(),
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
