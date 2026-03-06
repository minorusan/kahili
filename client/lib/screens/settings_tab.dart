import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../theme/kahili_theme.dart';

class SettingsTab extends StatefulWidget {
  final bool setupMode;
  final VoidCallback? onSetupComplete;

  const SettingsTab({super.key, this.setupMode = false, this.onSetupComplete});

  @override
  State<SettingsTab> createState() => SettingsTabState();
}

class SettingsTabState extends State<SettingsTab> {
  final _sentryTokenCtrl = TextEditingController();
  final _openaiKeyCtrl = TextEditingController();
  final _repoPathCtrl = TextEditingController();
  final _pollIntervalCtrl = TextEditingController();
  final _reportIntervalCtrl = TextEditingController();

  bool _loading = true;
  bool _applying = false;
  bool _obscureSentry = true;
  bool _obscureOpenai = true;

  List<Map<String, dynamic>> _prompts = [];
  final Map<String, TextEditingController> _promptCtrls = {};
  bool _loadingPrompts = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPrompts();
  }

  @override
  void dispose() {
    _sentryTokenCtrl.dispose();
    _openaiKeyCtrl.dispose();
    _repoPathCtrl.dispose();
    _pollIntervalCtrl.dispose();
    _reportIntervalCtrl.dispose();
    for (final ctrl in _promptCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await ApiClient.getSettings();
      if (!mounted) return;
      _sentryTokenCtrl.text = settings['SENTRY_TOKEN'] ?? '';
      _openaiKeyCtrl.text = settings['OPENAI_API_KEY'] ?? '';
      _repoPathCtrl.text = settings['REPO_PATH'] ?? '';
      _pollIntervalCtrl.text = settings['POLL_INTERVAL'] ?? '300';
      _reportIntervalCtrl.text = settings['REPORT_UPDATE_INTERVAL'] ?? '300';
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      // On first run the endpoint may 404 — show empty form
      _pollIntervalCtrl.text = '300';
      _reportIntervalCtrl.text = '60';
      setState(() => _loading = false);
    }
  }

  Future<void> _loadPrompts() async {
    try {
      final prompts = await ApiClient.getPrompts();
      if (!mounted) return;
      setState(() {
        _prompts = prompts;
        for (final p in prompts) {
          final name = p['name'] as String;
          _promptCtrls[name] = TextEditingController(text: p['template'] as String? ?? '');
        }
        _loadingPrompts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPrompts = false);
    }
  }

  Future<void> _savePrompt(String name) async {
    final ctrl = _promptCtrls[name];
    if (ctrl == null) return;

    try {
      await ApiClient.savePrompt(name, ctrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Prompt "$name" saved')),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to save prompt: $e');
    }
  }

  Future<void> _apply() async {
    // Validate required fields
    if (_sentryTokenCtrl.text.trim().isEmpty) {
      _showError('Sentry Auth Token is required');
      return;
    }
    if (_repoPathCtrl.text.trim().isEmpty) {
      _showError('Local Repo Path is required');
      return;
    }

    setState(() => _applying = true);
    try {
      await ApiClient.applySettings({
        'SENTRY_TOKEN': _sentryTokenCtrl.text.trim(),
        'OPENAI_API_KEY': _openaiKeyCtrl.text.trim(),
        'REPO_PATH': _repoPathCtrl.text.trim(),
        'POLL_INTERVAL': _pollIntervalCtrl.text.trim(),
        'REPORT_UPDATE_INTERVAL': _reportIntervalCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings applied, kahu restarted')),
      );
      widget.onSetupComplete?.call();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to apply settings: $e');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: KahiliColors.errorDark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.setupMode) ...[
            const Text(
              'Welcome to Kahili',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: KahiliColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Configure required settings to get started.',
              style: TextStyle(fontSize: 13, color: KahiliColors.textSecondary),
            ),
            const SizedBox(height: 24),
          ],

          // ── Required fields ──────────────────────────────────────
          _sectionHeader('Required'),
          const SizedBox(height: 12),

          _buildLabel('Sentry Auth Token'),
          const SizedBox(height: 4),
          TextField(
            controller: _sentryTokenCtrl,
            obscureText: _obscureSentry,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'sntrys_...',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureSentry ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: KahiliColors.textTertiary,
                ),
                onPressed: () => setState(() => _obscureSentry = !_obscureSentry),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          _buildHelp(
            'sentry.io \u2192 Settings \u2192 Auth Tokens \u2192 Create New Token.\n'
            'Scopes needed: project:read, event:read, org:read, member:read.',
          ),
          const SizedBox(height: 16),

          _buildLabel('OpenAI API Key'),
          const SizedBox(height: 4),
          TextField(
            controller: _openaiKeyCtrl,
            obscureText: _obscureOpenai,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'sk-...',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureOpenai ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: KahiliColors.textTertiary,
                ),
                onPressed: () => setState(() => _obscureOpenai = !_obscureOpenai),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          _buildHelp(
            'platform.openai.com \u2192 API Keys \u2192 Create new secret key.\n'
            'Billing must be set up on the OpenAI account.',
          ),
          const SizedBox(height: 16),

          _buildLabel('Local Repo Path'),
          const SizedBox(height: 4),
          TextField(
            controller: _repoPathCtrl,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              hintText: '/home/user/project',
              border: OutlineInputBorder(),
            ),
          ),
          _buildHelp('Absolute path to the Unity project git repo on this machine.'),
          const SizedBox(height: 28),

          // ── Optional fields ──────────────────────────────────────
          _sectionHeader('Optional'),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Poll Interval (sec)'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _pollIntervalCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: '300',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Report Interval (sec)'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _reportIntervalCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: '60',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // ── Apply button ─────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _applying ? null : _apply,
              child: _applying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text('Apply', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 32),

          // ── Agent Prompts ──────────────────────────────────────
          _sectionHeader('Agent Prompts'),
          const SizedBox(height: 4),
          const Text(
            'System prompts sent to AI agents. Use {{PLACEHOLDERS}} for dynamic values.',
            style: TextStyle(fontSize: 11, color: KahiliColors.textTertiary),
          ),
          const SizedBox(height: 12),

          if (_loadingPrompts)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            ..._prompts.map((p) {
              final name = p['name'] as String;
              final desc = p['description'] as String? ?? '';
              final isCustomized = p['isCustomized'] == true;
              return _promptEditor(name, desc, isCustomized);
            }),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _promptEditor(String name, String description, bool isCustomized) {
    final ctrl = _promptCtrls[name];
    if (ctrl == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: KahiliColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCustomized ? KahiliColors.flame.withAlpha(60) : KahiliColors.border,
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            collapsedIconColor: KahiliColors.textTertiary,
            iconColor: KahiliColors.flame,
            title: Row(
              children: [
                const Icon(Icons.smart_toy_outlined, size: 16, color: KahiliColors.flame),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: KahiliColors.textPrimary,
                    ),
                  ),
                ),
                if (isCustomized)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: KahiliColors.flame.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'CUSTOM',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: KahiliColors.flame,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: description.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      description,
                      style: const TextStyle(fontSize: 11, color: KahiliColors.textTertiary),
                    ),
                  )
                : null,
            children: [
              const Divider(height: 1, color: KahiliColors.border),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: ctrl,
                      maxLines: 15,
                      minLines: 8,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: KahiliColors.textPrimary,
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF08080E),
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
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _savePrompt(name),
                          style: TextButton.styleFrom(
                            foregroundColor: KahiliColors.flame,
                          ),
                          child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: KahiliColors.flame,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: KahiliColors.textSecondary,
      ),
    );
  }

  Widget _buildHelp(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: KahiliColors.textTertiary),
      ),
    );
  }
}
