import 'dart:convert';
import 'package:http/http.dart' as http;

/// Uploads a local image file to Cloudinary using an unsigned upload preset
/// and returns the resulting CDN URL. Unsigned presets are safe to embed in
/// a client app by design — Cloudinary scopes what they can do (folder,
/// formats, size limits) from the dashboard, no API secret involved.
///
/// Best-effort: image upload should never fail a cloud sync. Every method
/// returns null instead of throwing.
class CloudinaryUploadService {
  final String _cloudName;
  final String _uploadPreset;
  final http.Client _client;

  CloudinaryUploadService(this._cloudName, this._uploadPreset) : _client = http.Client();

  bool get isConfigured => _cloudName.isNotEmpty && _uploadPreset.isNotEmpty;

  Future<String?> uploadImage(String localFilePath) async {
    if (!isConfigured) return null;
    try {
      final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', localFilePath));

      final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['secure_url'] as String?;
    } catch (_) {
      return null;
    }
  }
}
