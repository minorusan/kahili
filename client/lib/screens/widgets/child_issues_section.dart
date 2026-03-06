import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/kahili_theme.dart';
import 'shared_widgets.dart';

class ChildIssuesSection extends StatefulWidget {
  final List<String> sentryLinks;
  final List<String> childIssueIds;
  final List<String> childStatuses;
  final void Function(List<String> selectedIds, List<String> selectedLinks) onArchivePressed;

  const ChildIssuesSection({
    super.key,
    required this.sentryLinks,
    required this.childIssueIds,
    required this.childStatuses,
    required this.onArchivePressed,
  });

  @override
  State<ChildIssuesSection> createState() => _ChildIssuesSectionState();
}

class _ChildIssuesSectionState extends State<ChildIssuesSection> {
  final Set<int> _selectedChildIndices = {};

  @override
  Widget build(BuildContext context) {
    final unresolvedCount = widget.childStatuses
        .where((s) => s == 'unresolved')
        .length;
    final hasSelection = _selectedChildIndices.isNotEmpty;

    // Split into unresolved and resolved/archived
    final unresolvedIndices = <int>[];
    final archivedIndices = <int>[];
    for (int i = 0; i < widget.sentryLinks.length; i++) {
      if (i < widget.childStatuses.length && widget.childStatuses[i] != 'unresolved') {
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
            Expanded(child: sectionHeader('Child Issues')),
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
          darkCard(
            child: Column(
              children: [
                for (int j = 0; j < unresolvedIndices.length; j++) ...[
                  if (j > 0) kahiliDivider(),
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
                    if (j > 0) kahiliDivider(),
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
              onPressed: () {
                final selectedIds = _selectedChildIndices
                    .where((i) => i < widget.childIssueIds.length)
                    .map((i) => widget.childIssueIds[i])
                    .toList();
                final selectedLinks = _selectedChildIndices
                    .where((i) => i < widget.sentryLinks.length)
                    .map((i) => widget.sentryLinks[i])
                    .toList();
                widget.onArchivePressed(selectedIds, selectedLinks);
              },
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
    final url = widget.sentryLinks[index];
    final isSelected = _selectedChildIndices.contains(index);
    final issueId = index < widget.childIssueIds.length
        ? widget.childIssueIds[index]
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
    final url = widget.sentryLinks[index];
    final issueId = index < widget.childIssueIds.length
        ? widget.childIssueIds[index]
        : '';
    final shortId = url.split('/').where((s) => s.isNotEmpty).lastOrNull ?? issueId;
    final status = index < widget.childStatuses.length
        ? widget.childStatuses[index]
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

  /// Call this from the parent after a successful archive to clear selection
  /// and update statuses locally.
  void clearSelectionAndMarkArchived() {
    setState(() {
      for (final idx in _selectedChildIndices) {
        if (idx < widget.childStatuses.length) {
          widget.childStatuses[idx] = 'ignored';
        }
      }
      _selectedChildIndices.clear();
    });
  }
}
