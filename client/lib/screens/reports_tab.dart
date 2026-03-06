import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/client_logger.dart';
import '../theme/kahili_theme.dart';
import 'widgets/shared_widgets.dart';
import 'report_detail.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => ReportsTabState();
}

class ReportsTabState extends State<ReportsTab> {
  List<String> _dates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  String? _error;

  Future<void> _loadDates() async {
    try {
      final dates = await ApiClient.getDailyReportDates();
      if (!mounted) return;
      setState(() {
        _dates = dates;
        _loading = false;
      });
    } catch (e, stack) {
      ClientLogger.error('ReportsTab._loadDates failed: $e', stack.toString());
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_dates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error != null ? 'Error loading reports' : 'No reports yet',
                style: const TextStyle(color: KahiliColors.textTertiary)),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(_error!, style: const TextStyle(color: KahiliColors.error, fontSize: 11),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () { setState(() { _loading = true; _error = null; }); _loadDates(); },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDates,
      child: CopyableSelectionArea(child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _dates.length,
        itemBuilder: (ctx, i) {
          final date = _dates[i];
          final isToday = date == _todayString();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: KahiliColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isToday ? KahiliColors.flame.withAlpha(60) : KahiliColors.border,
              ),
            ),
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ReportDetail(date: date)),
              ),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isToday ? KahiliColors.flame.withAlpha(20) : const Color(0xFF08080E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.summarize,
                  size: 20,
                  color: isToday ? KahiliColors.flame : KahiliColors.textTertiary,
                ),
              ),
              title: Text(
                'Report $date',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isToday ? KahiliColors.flame : KahiliColors.textPrimary,
                ),
              ),
              subtitle: isToday
                  ? const Text(
                      'Today \u00b7 Updated every minute',
                      style: TextStyle(fontSize: 11, color: KahiliColors.textTertiary),
                    )
                  : null,
              trailing: const Icon(Icons.chevron_right, color: KahiliColors.textTertiary, size: 20),
            ),
          );
        },
      )),
    );
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
