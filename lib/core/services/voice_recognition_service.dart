import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../utils/permission_service.dart';

/// One shared [SpeechToText] instance + initialization state for the whole
/// app. Previously each voice entry point (push-to-talk in the main shell,
/// the voice bottom sheet, the dedicated Voice Billing screen) owned its own
/// `SpeechToText()` and called `initialize()` — including a fresh
/// microphone-permission check — every single time that screen or sheet
/// opened, even when permission had already been granted. Routing every
/// entry point through this instance means the permission check and STT
/// initialization happen at most once per app session; after that, opening
/// the voice button anywhere just reuses the already-ready instance instead
/// of asking again.
class VoiceRecognitionService {
  VoiceRecognitionService._();
  static final VoiceRecognitionService instance = VoiceRecognitionService._();

  final SpeechToText speech = SpeechToText();
  bool _initialized = false;
  bool _available = false;

  bool get isAvailable => _available;

  void Function(dynamic error)? _onError;
  void Function(String status)? _onStatus;

  /// Ensures [speech] is permission-checked and initialized, doing that work
  /// only the first time it's ever called. [onError]/[onStatus] are updated
  /// on every call (cheap) so whichever screen is currently listening gets
  /// its own callbacks even though the underlying instance and its one-time
  /// initialization are shared.
  Future<bool> ensureReady(
    BuildContext context, {
    required void Function(dynamic error) onError,
    required void Function(String status) onStatus,
  }) async {
    _onError = onError;
    _onStatus = onStatus;

    if (_initialized) return _available;

    final granted = await PermissionService.requestMicrophone(context);
    if (!granted) return false;

    _available = await speech.initialize(
      onError: (e) => _onError?.call(e),
      onStatus: (s) => _onStatus?.call(s),
    );
    _initialized = true;
    return _available;
  }
}
