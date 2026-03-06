import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../theme/kahili_theme.dart';
import 'sentry_tab.dart';
import 'incoming_tab.dart';
import 'reports_tab.dart';
import 'settings_tab.dart';
import 'help_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  int? _backendBuild;
  bool _checkingConfig = true;
  bool _needsSetup = false;

  final _sentryTabKey = GlobalKey<State<SentryTab>>();
  final _incomingTabKey = GlobalKey<IncomingTabState>();
  final _reportsTabKey = GlobalKey<ReportsTabState>();
  final _settingsTabKey = GlobalKey<SettingsTabState>();
  final _helpTabKey = GlobalKey<HelpTabState>();

  @override
  void initState() {
    super.initState();
    _checkConfig();
  }

  Future<void> _checkConfig() async {
    try {
      final status = await ApiClient.getStatus();
      if (mounted) setState(() => _backendBuild = status['build'] as int?);
    } catch (_) {}

    try {
      final settings = await ApiClient.getSettings();
      final token = settings['SENTRY_TOKEN'] ?? '';
      if (mounted) {
        setState(() {
          _needsSetup = token.isEmpty;
          _checkingConfig = false;
        });
      }
    } catch (_) {
      // If settings endpoint fails, assume setup needed
      if (mounted) {
        setState(() {
          _needsSetup = true;
          _checkingConfig = false;
        });
      }
    }
  }

  void _onSetupComplete() {
    setState(() {
      _checkingConfig = true;
      _settingsTabKey.currentState?.dispose;
    });
    _checkConfig().then((_) {
      if (!_needsSetup && mounted) {
        setState(() => _tabIndex = 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingConfig) {
      return Scaffold(
        backgroundColor: KahiliColors.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_needsSetup) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: Column(
          children: [
            Expanded(
              child: SettingsTab(
                key: _settingsTabKey,
                setupMode: true,
                onSetupComplete: _onSetupComplete,
              ),
            ),
            _buildVersionBar(context),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                SentryTab(key: _sentryTabKey),
                IncomingTab(key: _incomingTabKey),
                ReportsTab(key: _reportsTabKey),
                SettingsTab(
                  key: _settingsTabKey,
                  onSetupComplete: _onSetupComplete,
                ),
                HelpTab(key: _helpTabKey),
              ],
            ),
          ),
          _buildVersionBar(context),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) {
          setState(() => _tabIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bug_report_outlined),
            selectedIcon: Icon(Icons.bug_report),
            label: 'Sentry',
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox),
            label: 'Incoming',
          ),
          NavigationDestination(
            icon: Icon(Icons.summarize_outlined),
            selectedIcon: Icon(Icons.summarize),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.help_outline),
            selectedIcon: Icon(Icons.help),
            label: 'Help',
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/eye-icon.png', height: 28),
          const SizedBox(width: 10),
          const Text(
            'Kahili',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      centerTitle: false,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                KahiliColors.flameDark,
                KahiliColors.flame,
                KahiliColors.flameDark,
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVersionBar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        'v1.0.0${_backendBuild != null ? ' \u00b7 build $_backendBuild' : ''}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
