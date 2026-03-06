import 'package:flutter/material.dart';
import '../../theme/kahili_theme.dart';

class InvestigatingBadge extends StatefulWidget {
  @override
  State<InvestigatingBadge> createState() => _InvestigatingBadgeState();
}

class _InvestigatingBadgeState extends State<InvestigatingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: KahiliColors.gold.withAlpha(15 + (_controller.value * 20).toInt()),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: KahiliColors.gold.withAlpha(40 + (_controller.value * 40).toInt()),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: KahiliColors.gold,
                  value: null,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'INVESTIGATING',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: KahiliColors.gold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
