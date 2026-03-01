import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../theme/kahili_theme.dart';
import 'sentry_tab.dart';
import 'incoming_tab.dart';
import 'reports_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  int? _backendBuild;

  final _sentryTabKey = GlobalKey<State<SentryTab>>();
  final _incomingTabKey = GlobalKey<IncomingTabState>();
  final _reportsTabKey = GlobalKey<ReportsTabState>();

  @override
  void initState() {
    super.initState();
    _fetchBuild();
  }

  Future<void> _fetchBuild() async {
    try {
      final status = await ApiClient.getStatus();
      if (mounted) setState(() => _backendBuild = status['build'] as int?);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/kahili_feather_icon_cropped.png', height: 28),
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
      ),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                SentryTab(key: _sentryTabKey),
                IncomingTab(key: _incomingTabKey),
                ReportsTab(key: _reportsTabKey),
              ],
            ),
          ),
          Container(
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
          ),
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
        ],
      ),
    );
  }
}
