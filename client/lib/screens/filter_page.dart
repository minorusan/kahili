import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/kahili_theme.dart';
import 'widgets/shared_widgets.dart';

class FilterSettings {
  final List<String> filterStrings;
  final String sortField; // 'lastSeen' or 'affectedUsers'
  final bool sortAscending;

  const FilterSettings({
    this.filterStrings = const [],
    this.sortField = 'lastSeen',
    this.sortAscending = false,
  });

  FilterSettings copyWith({
    List<String>? filterStrings,
    String? sortField,
    bool? sortAscending,
  }) {
    return FilterSettings(
      filterStrings: filterStrings ?? this.filterStrings,
      sortField: sortField ?? this.sortField,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  static Future<FilterSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return FilterSettings(
      filterStrings: prefs.getStringList('filterStrings') ?? [],
      sortField: prefs.getString('sortField') ?? 'lastSeen',
      sortAscending: prefs.getBool('sortAscending') ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('filterStrings', filterStrings);
    await prefs.setString('sortField', sortField);
    await prefs.setBool('sortAscending', sortAscending);
  }
}

class FilterPage extends StatefulWidget {
  const FilterPage({super.key});

  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  FilterSettings _settings = const FilterSettings();
  bool _loaded = false;
  final _filterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await FilterSettings.load();
    if (mounted) setState(() { _settings = settings; _loaded = true; });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _update(FilterSettings newSettings) {
    setState(() => _settings = newSettings);
    newSettings.save();
  }

  void _addFilter() {
    final text = _filterController.text.trim();
    if (text.isEmpty) return;
    if (_settings.filterStrings.contains(text)) return;
    _filterController.clear();
    _update(_settings.copyWith(
      filterStrings: [..._settings.filterStrings, text],
    ));
  }

  void _removeFilter(String filter) {
    _update(_settings.copyWith(
      filterStrings: _settings.filterStrings.where((f) => f != filter).toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_settings);
      },
      child: Scaffold(
        backgroundColor: KahiliColors.bg,
        appBar: AppBar(
          title: const Text('Filter & Sort', style: TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_settings),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: KahiliColors.border),
          ),
        ),
        body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : CopyableSelectionArea(child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Sort section ─────────────────────────────
            _sectionHeader('Sort'),
            const SizedBox(height: 8),
            _sortCard(),
            const SizedBox(height: 24),

            // ── Filter strings section ───────────────────
            _sectionHeader('Filter Strings'),
            const SizedBox(height: 8),
            _filterInputCard(),
            const SizedBox(height: 12),
            if (_settings.filterStrings.isNotEmpty) _filterChips(),
          ],
        )),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: KahiliColors.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _sortCard() {
    return Container(
      decoration: BoxDecoration(
        color: KahiliColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KahiliColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sort field
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Text('Sort by', style: TextStyle(fontSize: 12, color: KahiliColors.textTertiary)),
          ),
          _radioTile(
            title: 'Last seen (time)',
            selected: _settings.sortField == 'lastSeen',
            onTap: () => _update(_settings.copyWith(sortField: 'lastSeen')),
          ),
          _radioTile(
            title: 'Affected users',
            selected: _settings.sortField == 'affectedUsers',
            onTap: () => _update(_settings.copyWith(sortField: 'affectedUsers')),
          ),
          const Divider(height: 1, color: KahiliColors.border),

          // Sort direction
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Text('Direction', style: TextStyle(fontSize: 12, color: KahiliColors.textTertiary)),
          ),
          _radioTile(
            title: _settings.sortField == 'lastSeen' ? 'Newest first' : 'Most first',
            selected: !_settings.sortAscending,
            onTap: () => _update(_settings.copyWith(sortAscending: false)),
          ),
          _radioTile(
            title: _settings.sortField == 'lastSeen' ? 'Oldest first' : 'Fewest first',
            selected: _settings.sortAscending,
            onTap: () => _update(_settings.copyWith(sortAscending: true)),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _radioTile({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? KahiliColors.flame : KahiliColors.textTertiary,
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: selected ? KahiliColors.textPrimary : KahiliColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterInputCard() {
    return Container(
      decoration: BoxDecoration(
        color: KahiliColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KahiliColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _filterController,
              style: const TextStyle(fontSize: 14, color: KahiliColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Add filter string...',
                hintStyle: TextStyle(color: KahiliColors.textTertiary, fontSize: 14),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _addFilter(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: KahiliColors.flame),
            onPressed: _addFilter,
          ),
        ],
      ),
    );
  }

  Widget _filterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _settings.filterStrings.map((filter) {
        return Chip(
          label: Text(
            filter,
            style: const TextStyle(fontSize: 13, color: KahiliColors.textPrimary),
          ),
          deleteIcon: const Icon(Icons.close, size: 16),
          deleteIconColor: KahiliColors.textTertiary,
          onDeleted: () => _removeFilter(filter),
          backgroundColor: KahiliColors.surfaceBright,
          side: const BorderSide(color: KahiliColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );
      }).toList(),
    );
  }
}
