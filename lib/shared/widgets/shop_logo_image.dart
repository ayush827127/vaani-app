import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Resolves what to show for a shop's logo: the local file if it still
/// exists on this device, otherwise the Cloudinary URL cloud sync uploaded
/// it to (`Shop.logoUrl`), otherwise null (caller shows its own fallback,
/// e.g. an initial letter).
///
/// The local-file-first order matters: `logoPath` is meaningless off-device
/// and gets wiped whenever the app is uninstalled/reinstalled or the phone
/// changes, while `logoUrl` survives that because it's synced from the
/// cloud. Every screen that renders the shop logo must go through this (or
/// [fetchShopLogoBytes] for the PDF path) rather than checking `logoPath`
/// alone — checking only the local file is exactly what made a shop's logo
/// vanish after reinstall even though it had already been backed up.
Widget? resolveShopLogoImage({
  required String? logoPath,
  required String? logoUrl,
  required double size,
  BoxFit fit = BoxFit.cover,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  final hasFile = logoPath != null && logoPath.isNotEmpty && File(logoPath).existsSync();
  if (hasFile) {
    return Image.file(File(logoPath), width: size, height: size, fit: fit, errorBuilder: errorBuilder);
  }
  if (logoUrl != null && logoUrl.isNotEmpty) {
    return Image.network(logoUrl, width: size, height: size, fit: fit, errorBuilder: errorBuilder);
  }
  return null;
}

/// Same fallback order as [resolveShopLogoImage], but returns raw bytes for
/// contexts that can't use an `Image` widget — building the invoice PDF and
/// the payment-sheet receipt, both of which embed the logo as a
/// `pw.MemoryImage`. Best-effort: a network hiccup just means no logo on
/// that document, not a failed bill/payment.
Future<Uint8List?> fetchShopLogoBytes({
  required String? logoPath,
  required String? logoUrl,
}) async {
  if (logoPath != null && logoPath.isNotEmpty) {
    final f = File(logoPath);
    if (await f.exists()) return f.readAsBytes();
  }
  if (logoUrl != null && logoUrl.isNotEmpty) {
    try {
      final res = await http.get(Uri.parse(logoUrl));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {
      // offline / bad URL — fall through to no logo
    }
  }
  return null;
}
