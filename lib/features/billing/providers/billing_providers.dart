import 'package:flutter_riverpod/flutter_riverpod.dart';

// Increment this value to signal BillingScreen to open the inline voice sheet.
final voiceTriggerProvider = StateProvider<int>((ref) => 0);

// true while the PTT mic is actively recording.
final pttRecordingProvider = StateProvider<bool>((ref) => false);

// Non-null when a PTT transcript is ready; BillingScreen processes it then resets to null.
final pttTranscriptProvider = StateProvider<String?>((ref) => null);

// Live partial transcript while PTT recording; updated on every STT partial result.
final pttPartialTranscriptProvider = StateProvider<String>((ref) => '');
