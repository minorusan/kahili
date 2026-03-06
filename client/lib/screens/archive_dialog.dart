import 'package:flutter/material.dart';
import '../theme/kahili_theme.dart';
import '../api/api_client.dart';

enum ArchiveMode {
  forever,
  untilEscalating,
  forDuration,
  untilEvents,
  untilUsers,
}

class ArchiveDialog extends StatefulWidget {
  final List<String> issueIds;
  final List<String> sentryLinks;
  final String ruleName;
  final String ruleDescription;

  const ArchiveDialog({
    super.key,
    required this.issueIds,
    required this.sentryLinks,
    required this.ruleName,
    required this.ruleDescription,
  });

  @override
  State<ArchiveDialog> createState() => _ArchiveDialogState();
}

class _ArchiveDialogState extends State<ArchiveDialog> {
  final _commentController = TextEditingController();
  ArchiveMode _mode = ArchiveMode.untilEscalating;
  bool _submitting = false;

  // Duration mode
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 30));

  // Event count mode
  final _eventCountController = TextEditingController(text: '100');
  final _eventWindowController = TextEditingController(text: '10080');

  // User count mode
  final _userCountController = TextEditingController(text: '100');
  final _userWindowController = TextEditingController(text: '10080');

  @override
  void dispose() {
    _commentController.dispose();
    _eventCountController.dispose();
    _eventWindowController.dispose();
    _userCountController.dispose();
    _userWindowController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildArchiveParams() {
    switch (_mode) {
      case ArchiveMode.forever:
        return {'substatus': 'archived_forever'};
      case ArchiveMode.untilEscalating:
        return {'substatus': 'archived_until_escalating'};
      case ArchiveMode.forDuration:
        final minutes = _selectedDate.difference(DateTime.now()).inMinutes;
        return {'ignoreDuration': minutes.clamp(1, 525600)};
      case ArchiveMode.untilEvents:
        return {
          'ignoreCount': int.tryParse(_eventCountController.text) ?? 100,
          'ignoreWindow': int.tryParse(_eventWindowController.text) ?? 10080,
        };
      case ArchiveMode.untilUsers:
        return {
          'ignoreUserCount': int.tryParse(_userCountController.text) ?? 100,
          'ignoreUserWindow':
              int.tryParse(_userWindowController.text) ?? 10080,
        };
    }
  }

  Future<void> _submit() async {
    // Show confirmation dialog with rule warning
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KahiliColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: KahiliColors.border),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: KahiliColors.gold, size: 24),
            const SizedBox(width: 10),
            const Text('Confirm Archive',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'These issues are grouped by a rule. If the rule is inaccurate, you may archive issues that are still relevant.',
              style: TextStyle(
                fontSize: 13,
                color: KahiliColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KahiliColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KahiliColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: KahiliColors.cyan.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: KahiliColors.cyan.withAlpha(40)),
                    ),
                    child: Text(
                      widget.ruleName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: KahiliColors.cyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    widget.ruleDescription.isNotEmpty
                        ? widget.ruleDescription
                        : 'No description available',
                    style: const TextStyle(
                      fontSize: 12,
                      color: KahiliColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Archive ${widget.issueIds.length} issue${widget.issueIds.length == 1 ? '' : 's'}?',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KahiliColors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: KahiliColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: KahiliColors.flame,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Archive',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      final result = await ApiClient.archiveIssues(
        issueIds: widget.issueIds,
        archiveParams: _buildArchiveParams(),
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archive failed: $e')),
      );
      setState(() => _submitting = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: KahiliColors.flame,
              onPrimary: Colors.black,
              surface: KahiliColors.surfaceLight,
              onSurface: KahiliColors.textPrimary,
            ),
            dialogBackgroundColor: KahiliColors.surface,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  String _windowLabel(String minutes) {
    final m = int.tryParse(minutes) ?? 0;
    if (m <= 0) return '';
    if (m < 60) return '${m}m';
    if (m < 1440) return '${(m / 60).round()}h';
    return '${(m / 1440).round()}d';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KahiliColors.bg,
      appBar: AppBar(
        title: const Text('Archive Issues',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: KahiliColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Issue count header
          _card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: KahiliColors.flame.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: KahiliColors.flame.withAlpha(60)),
                    ),
                    child: Text(
                      '${widget.issueIds.length}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: KahiliColors.flame,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.issueIds.length == 1
                          ? 'issue selected for archiving'
                          : 'issues selected for archiving',
                      style: const TextStyle(
                        fontSize: 14,
                        color: KahiliColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Comment
          _sectionLabel('COMMENT'),
          const SizedBox(height: 6),
          _card(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: TextField(
                controller: _commentController,
                maxLines: 3,
                minLines: 2,
                style: const TextStyle(
                    fontSize: 13, color: KahiliColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Why are you archiving these issues?',
                  hintStyle: TextStyle(color: KahiliColors.textTertiary),
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding: EdgeInsets.all(12),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Archive mode
          _sectionLabel('ARCHIVE MODE'),
          const SizedBox(height: 6),
          _card(
            child: Column(
              children: [
                _modeOption(
                  ArchiveMode.untilEscalating,
                  Icons.trending_up,
                  'Until escalating',
                  'Reopens if the issue escalates',
                  KahiliColors.gold,
                ),
                _modeDivider(),
                _modeOption(
                  ArchiveMode.forever,
                  Icons.all_inclusive,
                  'Forever',
                  'Never reopens automatically',
                  KahiliColors.textTertiary,
                ),
                _modeDivider(),
                _modeOption(
                  ArchiveMode.forDuration,
                  Icons.calendar_today,
                  'Until date',
                  'Reopens after selected date',
                  KahiliColors.cyan,
                ),
                _modeDivider(),
                _modeOption(
                  ArchiveMode.untilEvents,
                  Icons.local_fire_department,
                  'Until event count',
                  'Reopens after N more events',
                  KahiliColors.flame,
                ),
                _modeDivider(),
                _modeOption(
                  ArchiveMode.untilUsers,
                  Icons.people,
                  'Until user count',
                  'Reopens after N more users',
                  KahiliColors.emerald,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Mode-specific options
          if (_mode == ArchiveMode.forDuration) ...[
            _sectionLabel('REOPEN DATE'),
            const SizedBox(height: 6),
            _card(
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.event, size: 20, color: KahiliColors.cyan),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: KahiliColors.textPrimary,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_selectedDate.difference(DateTime.now()).inDays} days from now',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: KahiliColors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 20, color: KahiliColors.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_mode == ArchiveMode.untilEvents) ...[
            _sectionLabel('EVENT THRESHOLD'),
            const SizedBox(height: 6),
            _card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _numberField(
                      controller: _eventCountController,
                      label: 'Event count',
                      hint: 'Number of events',
                      icon: Icons.local_fire_department,
                      iconColor: KahiliColors.flame,
                    ),
                    const SizedBox(height: 12),
                    _windowField(
                      controller: _eventWindowController,
                      label: 'Time window',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_mode == ArchiveMode.untilUsers) ...[
            _sectionLabel('USER THRESHOLD'),
            const SizedBox(height: 6),
            _card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _numberField(
                      controller: _userCountController,
                      label: 'User count',
                      hint: 'Number of users',
                      icon: Icons.people,
                      iconColor: KahiliColors.emerald,
                    ),
                    const SizedBox(height: 12),
                    _windowField(
                      controller: _userWindowController,
                      label: 'Time window',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 8),

          // Archive button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.archive, size: 20),
              label: Text(
                _submitting
                    ? 'Archiving...'
                    : 'Archive ${widget.issueIds.length} issue${widget.issueIds.length == 1 ? '' : 's'}',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: KahiliColors.flame,
                foregroundColor: Colors.black,
                disabledBackgroundColor: KahiliColors.flame.withAlpha(80),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: KahiliColors.textTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
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

  Widget _modeDivider() =>
      const Divider(height: 1, color: KahiliColors.border, indent: 50);

  Widget _modeOption(
      ArchiveMode mode, IconData icon, String title, String subtitle, Color color) {
    final selected = _mode == mode;
    return InkWell(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: selected
            ? BoxDecoration(
                color: color.withAlpha(8),
              )
            : null,
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? color : KahiliColors.textTertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? KahiliColors.textPrimary
                          : KahiliColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: KahiliColors.textTertiary),
                  ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? color : KahiliColors.textTertiary,
                  width: selected ? 2 : 1.5,
                ),
                color: selected ? color.withAlpha(30) : Colors.transparent,
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, color: KahiliColors.textSecondary)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontSize: 14,
              color: KahiliColors.textPrimary,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: KahiliColors.textTertiary),
              filled: true,
              fillColor: const Color(0xFF08080E),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            ),
          ),
        ),
      ],
    );
  }

  Widget _windowField({
    required TextEditingController controller,
    required String label,
  }) {
    final windowLabel = _windowLabel(controller.text);
    return Row(
      children: [
        const Icon(Icons.schedule, size: 18, color: KahiliColors.textTertiary),
        const SizedBox(width: 10),
        SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, color: KahiliColors.textSecondary)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontSize: 14,
              color: KahiliColors.textPrimary,
              fontFamily: 'monospace',
            ),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Minutes',
              hintStyle: const TextStyle(color: KahiliColors.textTertiary),
              suffixText: windowLabel.isNotEmpty ? '= $windowLabel' : null,
              suffixStyle: const TextStyle(
                  fontSize: 12, color: KahiliColors.textTertiary),
              filled: true,
              fillColor: const Color(0xFF08080E),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            ),
          ),
        ),
      ],
    );
  }
}
