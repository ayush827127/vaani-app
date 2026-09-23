import 'dart:io';
import 'package:flutter/material.dart';
import '../models/item.dart';

/// Displays a item image (file or network) with a letter-initial fallback.
/// Drop-in replacement for the colored letter-avatar used across all screens.
class ItemAvatar extends StatelessWidget {
  final Item item;
  final double size;
  final Color catColor;
  final double borderRadiusValue;

  const ItemAvatar({
    super.key,
    required this.item,
    required this.size,
    required this.catColor,
    this.borderRadiusValue = 10,
  });

  @override
  Widget build(BuildContext context) {
    final path = item.imagePath;
    final hasImage = path != null && path.isNotEmpty;
    final isNetwork = hasImage && (path.startsWith('http://') || path.startsWith('https://'));
    final isFile = hasImage && !isNetwork;
    final fileExists = isFile && File(path).existsSync();
    // item.imageUrl is the Cloudinary URL cloud sync uploads to
    // specifically so a photo taken on one device shows up on others (see
    // the v8 migration in database_helper.dart) — falling back to it here
    // when there's no local file is what actually makes that work. Without
    // this, every device other than the one the photo was taken on shows
    // just the letter-avatar forever, even though the image exists in sync.
    final networkFallback = !fileExists && (item.imageUrl?.isNotEmpty ?? false)
        ? item.imageUrl
        : (isNetwork ? path : null);

    Widget imageChild;

    if (fileExists) {
      imageChild = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initial(),
      );
    } else if (networkFallback != null) {
      imageChild = Image.network(
        networkFallback,
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
        child: (networkFallback != null || fileExists)
            ? imageChild
            : Center(child: imageChild),
      ),
    );
  }

  Widget _initial() {
    return Center(
      child: Text(
        item.name.isNotEmpty ? item.name[0].toUpperCase() : 'P',
        style: TextStyle(
          color: catColor,
          fontSize: size * 0.44,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
