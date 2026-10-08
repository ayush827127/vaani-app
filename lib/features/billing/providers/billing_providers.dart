import 'package:flutter_riverpod/flutter_riverpod.dart';

// Increment this value to signal BillingScreen to open the inline voice sheet.
final voiceTriggerProvider = StateProvider<int>((ref) => 0);

// true while the PTT mic is actively recording.
final pttRecordingProvider = StateProvider<bool>((ref) => false);

// Non-null when a PTT transcript is ready; BillingScreen processes it then resets to null.
final pttTranscriptProvider = StateProvider<String?>((ref) => null);

// Live partial transcript while PTT recording; updated on every STT partial result.
final pttPartialTranscriptProvider = StateProvider<String>((ref) => '');

// True once any voice action (PTT, the voice sheet, or Voice Billing) has
// actually modified the current cart. Reset automatically whenever the cart
// becomes empty (see billing_screen.dart's ref.listen on cartProvider) —
// covers every way the cart can clear (voice "clear cart", the manual clear
// button, or after a completed checkout) without needing a reset call at
// each site individually. Distinguishes voice- from manually-created
// invoices for Invoice.isVoiceCreated (analytics only now — both count
// equally against the plan's combined invoiceMonthlyLimit, see
// InvoiceRepository.countInvoicesThisMonth).
final cartVoiceOriginProvider = StateProvider<bool>((ref) => false);
