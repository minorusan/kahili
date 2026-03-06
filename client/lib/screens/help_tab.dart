import 'package:flutter/material.dart';
import '../theme/kahili_theme.dart';
import 'faq_subtab.dart';
import 'develop_subtab.dart';

class HelpTab extends StatefulWidget {
  const HelpTab({super.key});

  @override
  State<HelpTab> createState() => HelpTabState();
}

class HelpTabState extends State<HelpTab> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: KahiliColors.surfaceLight,
          child: TabBar(
            controller: _tabCtrl,
            indicatorColor: KahiliColors.flame,
            indicatorWeight: 2,
            labelColor: KahiliColors.flame,
            unselectedLabelColor: KahiliColors.textTertiary,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
            tabs: const [
              Tab(text: 'FAQ'),
              Tab(text: 'Develop'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: const [
              FaqSubtab(),
              DevelopSubtab(),
            ],
          ),
        ),
      ],
    );
  }
}
