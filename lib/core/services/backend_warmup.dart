import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Fires a single best-effort GET at the backend's `/health` route as early
/// as possible in the app's lifecycle (app launch, and again when the login
/// screen appears). The backend runs on a free-tier host that sleeps after
/// ~15 minutes idle and can take up to a minute to wake up on the next real
/// request — pinging it here, well before the user reaches Send OTP, gives
/// it a head start so OTP send/verify rarely has to eat the full cold-start
/// wait itself. Never throws and nothing awaits this.
void warmUpBackend() {
  final baseUrl = dotenv.env['BACKEND_API_BASE_URL'] ?? '';
  if (baseUrl.isEmpty) return;
  http
      .get(Uri.parse('$baseUrl/health'))
      .timeout(const Duration(seconds: 60))
      .then((_) => debugPrint('[warmup] backend is awake'))
      .catchError((Object e) => debugPrint('[warmup] backend ping failed: $e'));
}
