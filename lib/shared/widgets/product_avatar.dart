import 'dart:io';
import 'package:flutter/material.dart';
import '../models/product.dart';

/// Displays a product image (file or network) with a letter-initial fallback.
/// Drop-in replacement for the colored letter-avatar used across all screens.
class ProductAvatar extends StatelessWidget {
  final Product product;
  final double size;
  final Color catColor;
  final double borderRadiusValue;

  const ProductAvatar({
    super.key,
    required this.product,
    required this.size,
    required this.catColor,
    this.borderRadiusValue = 10,
  });

  @override
  Widget build(BuildContext context) {
    final path = product.imagePath;
    final hasImage = path != null && path.isNotEmpty;
    final isNetwork = hasImage && (path.startsWith('http://') || path.startsWith('https://'));
    final isFile = hasImage && !isNetwork;
    final fileExists = isFile && File(path).existsSync();

    Widget imageChild;

    if (isNetwork) {
      imageChild = Image.network(
        path,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initial(),
      );
    } else if (fileExists) {
      imageChild = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initial(),
      );
    } else {
      imageChild = _initial();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadiusValue),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: catColor.withValues(alpha: 0.15),
          border: Border.all(color: catColor.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(borderRadiusValue),
        ),
        child: (isNetwork || fileExists)
            ? imageChild
            : Center(child: imageChild),
      ),
    );
  }

  Widget _initial() {
    return Center(
      child: Text(
        product.name.isNotEmpty ? product.name[0].toUpperCase() : 'P',
        style: TextStyle(
          color: catColor,
          fontSize: size * 0.44,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
