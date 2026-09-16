import 'dart:async';
import 'dart:io';

/// Turns a raw network exception into a short, user-facing message.
///
/// The backend runs on a free-tier host that sleeps after ~15 minutes of
/// inactivity and can take up to ~50s to wake up on the next request — a
/// plain timeout there is routine, not a real failure, so it gets more
/// reassuring copy than a generic error.
String friendlyNetworkError(Object error) {
  if (error is TimeoutException) {
    return "The server is waking up — this can take up to a minute the first time. Please try again.";
  }
  if (error is SocketException) {
    return "Couldn't reach the server — check your internet connection and try again.";
  }
  if (error is FormatException || error is HttpException) {
    // A response body mentioning "HTTPS port" is the signature of a TLS
    // termination error — something between the phone and the server
    // downgraded the HTTPS request to plain HTTP (seen with carrier data-saver
    // proxies and some device-level "smart network" features), not the app
    // server itself. That's a different fix (network settings) from a cold
    // start, so it gets its own message instead of the generic one below.
    if (error.toString().contains('HTTPS port')) {
      return "Your network seems to be altering secure connections — try switching to Wi-Fi, "
          "or turn off Data Saver / VPN / proxy on your phone, then try again.";
    }
    return "The server is still starting up — please try again in a few seconds.";
  }
  final message = error.toString();
  return message.startsWith('Exception: ') ? message.substring(11) : message;
}

/// The raw exception's type and message, e.g.
/// "SocketException: Failed host lookup: '...' (OS Error: ...)" — shown
/// alongside [friendlyNetworkError] so a real connectivity problem (DNS
/// failure, TLS handshake, OS-level connect timeout, etc.) is visible and
/// reportable instead of hidden behind the friendly copy, which otherwise
/// looks identical whether the cause is "server asleep" (routine) or an
/// actual unreachable-host problem (not routine, needs investigating).
String technicalErrorDetail(Object error) => '${error.runtimeType}: $error';
