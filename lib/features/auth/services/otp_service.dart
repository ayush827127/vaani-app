import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class OtpService {
  OtpService._();
  static final OtpService instance = OtpService._();

  final http.Client _client = http.Client();

  String get _baseUrl => dotenv.env['BACKEND_API_BASE_URL'] ?? '';

  /// POSTs [body] to [path] and decodes the JSON response, retrying the
  /// whole request when the body isn't valid JSON. On the free-tier host, a
  /// request that lands mid-cold-start gets back the host's own HTML
  /// placeholder page instead of the API response — that's a routine, brief
  /// state (not a real error), so a couple of retries a few seconds apart
  /// almost always finds the backend awake for the real request, and the
  /// caller never has to know a retry happened.
  Future<Map<String, dynamic>?> _postJson(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl$path');
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          // Generous timeout: the backend runs on a free-tier host that can
          // take up to ~50s to wake up from sleep on the first request.
          .timeout(const Duration(seconds: 60));

      try {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      } on FormatException {
        // Re-thrown with the actual status + a body snippet — a plain
        // FormatException here could mean the free-tier host was still
        // booting, but it can just as easily be a Cloudflare/Render error
        // page or a mobile-carrier proxy interfering with the connection,
        // which look identical from here (non-JSON body) but need different
        // fixes. The snippet is what tells those apart, and network_error.dart
        // pattern-matches it to pick the right user-facing message.
        final snippet = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
        final richError = FormatException(
          'Non-JSON response from $uri — HTTP ${response.statusCode}, body: $snippet',
        );
        // A TLS-downgrade proxy (see network_error.dart) will fail the same
        // way every time — retrying just delays showing the user the message
        // that actually tells them what to do.
        if (attempt == maxAttempts || snippet.contains('HTTPS port')) throw richError;
        debugPrint('[OTP] non-JSON response from $path (cold start?), retrying — attempt $attempt/$maxAttempts');
        await Future.delayed(const Duration(seconds: 5));
      }
    }
    throw StateError('unreachable');
  }

  /// Requests a real SMS OTP for [phone] via the backend. Throws on failure
  /// (offline, rate-limited, SMS provider error) — callers should catch this
  /// and show the message to the user.
  Future<void> sendOtp(String phone) async {
    final envelope = await _postJson('/api/shop/auth/send-otp', {'phone': phone});
    if (envelope?['success'] != true) {
      final message = envelope?['error']?['message'] as String? ?? 'Failed to send OTP';
      debugPrint('[OTP] send failed — $message');
      throw Exception(message);
    }
  }

  /// Verifies [entered] against the OTP sent to [phone]. Returns a short-lived
  /// otpToken on success (required by shop register/login) — `null` on a
  /// wrong/expired OTP (a real HTTP response, just not a success one).
  ///
  /// A network failure (offline, timeout, server still waking up) instead
  /// *throws* rather than returning null — callers must not treat "couldn't
  /// reach the server" the same as "wrong code", since showing "Incorrect
  /// OTP" for a connectivity problem is both wrong and unhelpful.
  Future<String?> verifyOtp(String phone, String entered) async {
    final envelope = await _postJson('/api/shop/auth/verify-otp', {'phone': phone, 'otp': entered});
    if (envelope?['success'] != true) {
      debugPrint('[OTP] verify failed');
      return null;
    }
    return envelope?['data']?['otpToken'] as String?;
  }
}
