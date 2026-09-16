import 'dart:io';

/// Forces every `dart:io HttpClient` in the app (which is what every
/// `package:http` client we use wraps internally) to resolve hosts and
/// connect over IPv4 only.
///
/// Root cause this works around: `HttpClient` does not race IPv4/IPv6 the
/// way browsers do (no "Happy Eyeballs") — it just tries whatever address
/// DNS hands back first. On networks with a present-but-dead IPv6 route
/// (common on Indian mobile carriers), that means the connection attempt
/// silently hangs on the broken IPv6 path until the OS-level socket timeout
/// (~a minute), even though the same host is instantly reachable over IPv4 —
/// exactly the "works in Chrome, times out in the app" symptom this fixes.
class Ipv4HttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      final addresses = await InternetAddress.lookup(uri.host, type: InternetAddressType.IPv4);
      final task = await Socket.startConnect(addresses.first, uri.port);
      if (!uri.isScheme('https')) return task;
      // Setting a custom connectionFactory makes HttpClient skip its own
      // SecureSocket upgrade for https:// requests entirely (see
      // _HttpClientConnection._openUrl in the Dart SDK: it only auto-secures
      // when connectionFactory is null) — every https:// request from this
      // app was going out as plain HTTP to the origin's TLS port, which the
      // origin correctly rejected. `host: uri.host` (not the resolved IP)
      // keeps SNI and certificate hostname checks pointed at the real domain.
      return ConnectionTask.fromSocket<Socket>(
        task.socket.then<Socket>(
          (socket) => SecureSocket.secure(socket, host: uri.host, context: context),
        ),
        task.cancel,
      );
    };
    return client;
  }
}
