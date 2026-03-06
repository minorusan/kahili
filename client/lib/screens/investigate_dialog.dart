import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';
import '../theme/kahili_theme.dart';

class InvestigateDialog extends StatefulWidget {
  final String motherIssueId;
  final String issueTitle;

  const InvestigateDialog({
    super.key,
    required this.motherIssueId,
    required this.issueTitle,
  });

  /// Returns true if investigation was started
  static Future<bool> show(BuildContext context, {
    required String motherIssueId,
    required String issueTitle,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InvestigateDialog(
        motherIssueId: motherIssueId,
        issueTitle: issueTitle,
      ),
    );
    return result ?? false;
  }

  @override
  State<InvestigateDialog> createState() => _InvestigateDialogState();
}

class _InvestigateDialogState extends State<InvestigateDialog> {
  bool _useTags = false; // false = branches, true = tags
  final _searchController = TextEditingController();
  final _promptController = TextEditingController();
  final _searchFocus = FocusNode();

  RepoInfo? _repoInfo;
  bool _loadingRepo = true;
  bool _starting = false;
  String? _error;

  List<String> _suggestions = [];
  String? _selectedRef;

  @override
  void initState() {
    super.initState();
    _loadRepoInfo();
    _searchController.addListener(_updateSuggestions);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _promptController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadRepoInfo() async {
    try {
      final info = await ApiClient.getRepoInfo();
      setState(() {
        _repoInfo = info;
        _loadingRepo = false;
      });
    } catch (e) {
      setState(() {
        _loadingRepo = false;
        _error = 'Failed to load repo info: $e';
      });
    }
  }

  void _updateSuggestions() {
    final query = _searchController.text.toLowerCase().trim();
    if (_repoInfo == null || query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    final source = _useTags ? _repoInfo!.tags : _repoInfo!.branches;
    setState(() {
      _suggestions = source
          .where((ref) => ref.toLowerCase().contains(query))
          .take(8)
          .toList();
    });
  }

  void _selectRef(String ref) {
    setState(() {
      _selectedRef = ref;
      _searchController.text = ref;
      _suggestions = [];
    });
    _searchFocus.unfocus();
  }

  void _toggleMode(bool useTags) {
    setState(() {
      _useTags = useTags;
      _selectedRef = null;
      _searchController.clear();
      _suggestions = [];
    });
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await ApiClient.startInvestigation(
        motherIssueId: widget.motherIssueId,
        branch: _selectedRef,
        additionalPrompt: _promptController.text.trim().isEmpty
            ? null
            : _promptController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _starting = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: KahiliColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: KahiliColors.flame, width: 2),
        ),
      ),
      child: SelectionArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KahiliColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            const Text(
              'Start Investigation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KahiliColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.issueTitle.split('\n').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: KahiliColors.textTertiary),
            ),
            const SizedBox(height: 20),

            // Branch/Tag toggle
            Row(
              children: [
                const Text(
                  'Reference',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KahiliColors.textSecondary,
                  ),
                ),
                const Spacer(),
                _toggleChip('Branches', !_useTags, () => _toggleMode(false)),
                const SizedBox(width: 6),
                _toggleChip('Tags', _useTags, () => _toggleMode(true)),
              ],
            ),
            const SizedBox(height: 10),

            // Search input
            if (_loadingRepo)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: const TextStyle(
                  color: KahiliColors.textPrimary,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: _useTags ? 'Search tags...' : 'Search branches...',
                  hintStyle: const TextStyle(color: KahiliColors.textTertiary),
                  prefixIcon: const Icon(Icons.search, size: 20, color: KahiliColors.textTertiary),
                  suffixIcon: _selectedRef != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: KahiliColors.textTertiary),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _selectedRef = null);
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: KahiliColors.surfaceLight,
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
                    borderSide: const BorderSide(color: KahiliColors.flame, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),

              // Suggestions dropdown
              if (_suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: KahiliColors.surfaceBright,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: KahiliColors.border),
                  ),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final ref = _suggestions[index];
                      return InkWell(
                        onTap: () => _selectRef(ref),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Text(
                            ref,
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                              color: KahiliColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],

            const SizedBox(height: 20),

            // Prompt input
            const Text(
              'Additional prompt (optional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: KahiliColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _promptController,
              maxLines: 3,
              style: const TextStyle(color: KahiliColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Focus on... / Check if... / Look at...',
                hintStyle: const TextStyle(color: KahiliColors.textTertiary),
                filled: true,
                fillColor: KahiliColors.surfaceLight,
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
                  borderSide: const BorderSide(color: KahiliColors.flame, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: KahiliColors.error.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: KahiliColors.error.withAlpha(40)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: KahiliColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(fontSize: 12, color: KahiliColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Start button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _starting ? null : _start,
                style: FilledButton.styleFrom(
                  backgroundColor: KahiliColors.flame,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: KahiliColors.surfaceBright,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _starting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: KahiliColors.textPrimary,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Start Investigation',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      )),
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? KahiliColors.flame.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? KahiliColors.flame.withAlpha(80) : KahiliColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? KahiliColors.flame : KahiliColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
