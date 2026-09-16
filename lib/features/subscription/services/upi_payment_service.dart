import 'package:url_launcher/url_launcher.dart';

/// Thrown when no UPI app is installed to handle the payment intent.
class UpiPaymentException implements Exception {
  final String message;
  const UpiPaymentException(this.message);
  @override
  String toString() => message;
}

/// Launches a generic `upi://pay` deep link — the standard UPI intent every
/// UPI app (Google Pay, PhonePe, Paytm, BHIM, a bank's own app, ...)
/// registers itself to handle, so the device's own app chooser decides
/// which one opens rather than this app hardcoding any single one.
///
/// Launching successfully means a UPI app opened with the payment details
/// pre-filled — it is NOT proof that money moved. A plain VPA has no
/// server-verifiable payment webhook (that needs a payment gateway/PSP,
/// which isn't in play here), so this deliberately returns nothing the
/// caller could mistake for a payment confirmation. Subscription activation
/// only ever happens via PaymentClaim + admin confirmation — see that
/// model's doc comment on the backend.
class UpiPaymentService {
  static const String payeeVpa = '8271274460@axl';
  static const String payeeName = 'Vaani';

  /// [reference] is used as both the transaction note and transaction ref
  /// so it shows up in the UPI app and the payer's bank/UPI statement —
  /// it's what lets an admin match this payment to the PaymentClaim
  /// carrying the same reference.
  static Future<void> launch({required double amount, required String reference}) async {
    final uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': payeeVpa,
        'pn': payeeName,
        'am': amount.toStringAsFixed(2),
        'cu': 'INR',
        'tn': reference,
        'tr': reference,
      },
    );

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw const UpiPaymentException(
        'No UPI app found on this device. Install Google Pay, PhonePe, or another UPI app to pay.',
      );
    }
  }
}
