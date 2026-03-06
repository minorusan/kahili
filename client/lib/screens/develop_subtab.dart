import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';
import '../theme/kahili_theme.dart';
import 'develop_ask_page.dart';
import 'develop_detail_page.dart';

class DevelopSubtab extends StatefulWidget {
  const DevelopSubtab({super.key});

  @override
  State<DevelopSubtab> createState() => _DevelopSubtabState();
}

class _DevelopSubtabState extends State<DevelopSubtab> {
  List<DevelopRequestSummary> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final requests = await ApiClient.getDevelopRequests();
      if (mounted) {
        setState(() {
          _requests = requests;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAskPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DevelopAskPage()),
    );
    _load();
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DevelopDetailPage(requestId: id)),
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
        '${_pad(local.hour)}:${_pad(local.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _openAskPage,
        backgroundColor: KahiliColors.flame,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
      body: _requests.isEmpty
          ? _emptyState()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: _requests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _requestTile(_requests[index]),
              ),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.build_outlined, size: 48, color: KahiliColors.textTertiary),
          SizedBox(height: 12),
          Text(
            'No feature requests yet',
            style: TextStyle(fontSize: 16, color: KahiliColors.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            'Tap + to request a feature',
            style: TextStyle(fontSize: 13, color: KahiliColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _requestTile(DevelopRequestSummary r) {
    final Color statusColor;
    final IconData statusIcon;
    switch (r.status) {
      case 'completed':
        statusColor = KahiliColors.emerald;
        statusIcon = Icons.check_circle;
        break;
      case 'running':
        statusColor = KahiliColors.gold;
        statusIcon = Icons.hourglass_top;
        break;
      case 'rejected':
        statusColor = KahiliColors.flame;
        statusIcon = Icons.block;
        break;
      default:
        statusColor = KahiliColors.error;
        statusIcon = Icons.error_outline;
    }

    return GestureDetector(
      onTap: () => _openDetail(r.id),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KahiliColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KahiliColors.border),
        ),
        child: Row(
          children: [
            Icon(statusIcon, size: 16, color: statusColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.request,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: KahiliColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          r.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(r.startedAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: KahiliColors.textTertiary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 20, color: KahiliColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
