import 'dart:io';
import 'package:flutter/material.dart';
import '../models/customer.dart';

/// Displays a customer's profile photo (local file) with a letter-initial
/// fallback — the one place this rendering logic lives, so every screen that
/// shows a customer (list, details, checkout picker) stays in sync.
class CustomerAvatar extends StatelessWidget {
  final Customer customer;
  final double size;
  final Color? color;

  const CustomerAvatar({
    super.key,
    required this.customer,
    required this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final path = customer.imagePath;
    final hasFile = path != null && path.isNotEmpty && File(path).existsSync();
    final avatarColor = color ?? Theme.of(context).colorScheme.primary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: avatarColor.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: avatarColor.withValues(alpha: 0.4)),
      ),
      child: ClipOval(
        child: hasFile
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, __, ___) => _initial(avatarColor),
              )
            : _initial(avatarColor),
      ),
    );
  }

  Widget _initial(Color avatarColor) => Center(
        child: Text(
          customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
          style: TextStyle(
            color: avatarColor,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}
