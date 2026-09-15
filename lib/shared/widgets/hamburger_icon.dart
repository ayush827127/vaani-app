import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class HamburgerIcon extends StatelessWidget {
  const HamburgerIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _HLine(width: 22),
          SizedBox(height: 5),
          _HLine(width: 16),
          SizedBox(height: 5),
          _HLine(width: 12),
        ],
      ),
    );
  }
}

class _HLine extends StatelessWidget {
  final double width;
  const _HLine({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}
