import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';
import '../theme/kahili_theme.dart';
import 'help_ask_page.dart';
import 'help_detail_page.dart';

class FaqSubtab extends StatefulWidget {
  const FaqSubtab({super.key});

  @override
  State<FaqSubtab> createState() => _FaqSubtabState();
}

class _FaqSubtabState extends State<FaqSubtab> {
  List<HelpQuestionSummary> _questions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final questions = await ApiClient.getHelpQuestions();
      if (mounted) {
        setState(() {
          _questions = questions;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAskPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HelpAskPage()),
    );
    _load();
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HelpDetailPage(questionId: id)),
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
      body: _questions.isEmpty
          ? _emptyState()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: _questions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _questionTile(_questions[index]),
              ),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.help_outline, size: 48, color: KahiliColors.textTertiary),
          SizedBox(height: 12),
          Text(
            'No questions yet',
            style: TextStyle(fontSize: 16, color: KahiliColors.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            'Tap + to ask about Kahili',
            style: TextStyle(fontSize: 13, color: KahiliColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _questionTile(HelpQuestionSummary q) {
    final statusColor = q.status == 'completed'
        ? KahiliColors.emerald
        : q.status == 'running'
            ? KahiliColors.gold
            : KahiliColors.error;

    return GestureDetector(
      onTap: () => _openDetail(q.id),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KahiliColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KahiliColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.question,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: KahiliColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(q.startedAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: KahiliColors.textTertiary,
                      fontFamily: 'monospace',
                    ),
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
