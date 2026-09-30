import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'transport.dart';

/// Which addresses the app may open a socket to (CLAUDE.md 4).
///
/// TapeDash is strictly offline. A WiFi ELM327 is a small access point of its
/// own, so its address is on a private network; nothing else is ever a reason to
/// open a socket. Allowed: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`,
/// loopback (`127.0.0.0/8`, `::1`, which is also how a dev machine's simulator is
/// reached) and link-local (`169.254.0.0/16`, `fe80::/10`). The Android emulator's
/// host, `10.0.2.2`, is in `10.0.0.0/8`.
///
/// **Only literal addresses.** A host name would be looked up, and a look-up is
/// itself a request to the network, so a name is refused whatever it says.
abstract final class NetworkGuard {
  /// Whether [host] is an address a socket may be opened to.
  static bool allows(String host) {
    final address = InternetAddress.tryParse(host.trim());
    if (address == null) return false;
    return allowsAddress(address);
  }

  static bool allowsAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    switch (address.type) {
      case InternetAddressType.IPv4:
        return _allowsV4(bytes);
      case InternetAddressType.IPv6:
        return _allowsV6(bytes);
      default:
        return false;
    }
  }

  static bool _allowsV4(List<int> b) {
    if (b.length != 4) return false;
    if (b[0] == 10) return true;
    if (b[0] == 127) return true;
    if (b[0] == 192 && b[1] == 168) return true;
    if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
    if (b[0] == 169 && b[1] == 254) return true;
    return false;
  }

  static bool _allowsV6(List<int> b) {
    if (b.length != 16) return false;
    // ::1, loopback.
    final loopback = b.take(15).every((x) => x == 0) && b[15] == 1;
    if (loopback) return true;
    // fe80::/10, link-local.
    if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return true;
    // ::ffff:a.b.c.d, an IPv4 address in IPv6 clothes: the same rule for it.
    final mapped =
        b.take(10).every((x) => x == 0) && b[10] == 0xff && b[11] == 0xff;
    if (mapped) return _allowsV4(b.sublist(12));
    return false;
  }
}

/// The address a WiFi adapter is usually found at.
const String defaultWifiHost = '192.168.0.10';

/// The port a WiFi ELM327 usually listens on.
const int defaultWifiPort = 35000;

/// Opens a socket. It is here so that a test can give one that is not real; the
/// address has always passed [NetworkGuard] by the time it is called.
typedef SocketConnector =
    Future<Socket> Function(String host, int port, Duration timeout);

Future<Socket> _connectSocket(String host, int port, Duration timeout) =>
    Socket.connect(host, port, timeout: timeout);

/// Bytes on the wire are Latin-1: an ELM327 speaks ASCII, and anything else is
/// noise that has to survive the trip.
const Latin1Codec _bytes = Latin1Codec(allowInvalid: true);

/// A [Transport] to a WiFi ELM327 (CLAUDE.md 4, 5): a TCP socket, to a private
/// address only.
///
/// **All socket code in the app is in this file.** [connect] refuses an address
/// [NetworkGuard] does not allow before any socket exists, with
/// [TransportFailure.unreachable].
class WifiTransport implements Transport {
  WifiTransport({
    this.host = defaultWifiHost,
    this.port = defaultWifiPort,
    this.connectTimeout = const Duration(seconds: 6),
    SocketConnector? connector,
  }) : _connector = connector ?? _connectSocket;

  final String host;
  final int port;
  final Duration connectTimeout;
  final SocketConnector _connector;

  final StreamController<String> _incoming = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast(sync: true);

  TransportState _current = const TransportState.disconnected();
  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;
  int _generation = 0;

  @override
  TransportState get currentState => _current;

  @override
  Stream<TransportState> get state => _states.stream;

  @override
  Stream<String> get incoming => _incoming.stream;

  void _set(TransportState next) {
    if (next == _current) return;
    _current = next;
    _states.add(next);
  }

  @override
  Future<void> connect() async {
    if (_current.status != TransportStatus.disconnected) return;
    final host = this.host.trim();
    if (!NetworkGuard.allows(host)) {
      const failure = TransportFailure.unreachable;
      _set(const TransportState.disconnected(failure: failure));
      throw TransportException(
        failure,
        'TapeDash only talks to adapters on a private network; $host is not one',
      );
    }
    final generation = ++_generation;
    _set(TransportState.connecting);
    final Socket socket;
    try {
      socket = await _connector(host, port, connectTimeout);
    } on Object catch (error) {
      if (generation != _generation) {
        throw const TransportException(TransportFailure.cancelled);
      }
      const failure = TransportFailure.unreachable;
      _set(const TransportState.disconnected(failure: failure));
      throw TransportException(failure, '$error');
    }
    if (generation != _generation) {
      // A disconnect came while this was being made.
      socket.destroy();
      throw const TransportException(TransportFailure.cancelled);
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    _subscription = socket.listen(
      (data) => _incoming.add(_bytes.decode(data)),
      onError: (Object _) => _dropped(generation),
      onDone: () => _dropped(generation),
      cancelOnError: true,
    );
    _set(TransportState.connected);
  }

  /// The far end closed, or the link failed.
  void _dropped(int generation) {
    if (generation != _generation || _socket == null) return;
    _release();
    _set(const TransportState.disconnected(failure: TransportFailure.lost));
  }

  void _release() {
    _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
  }

  @override
  Future<void> disconnect() async {
    _generation++;
    final was = _current;
    _release();
    if (was.status != TransportStatus.disconnected) {
      _set(const TransportState.disconnected());
    } else if (was.failure != null) {
      // An explicit disconnect after a failure clears it.
      _set(const TransportState.disconnected());
    }
  }

  @override
  Future<void> write(String data) async {
    final socket = _socket;
    if (socket == null || !_current.isConnected) {
      throw const TransportException(TransportFailure.notConnected);
    }
    try {
      socket.add(_bytes.encode(data));
      await socket.flush();
    } on Object catch (error) {
      _dropped(_generation);
      throw TransportException(TransportFailure.lost, '$error');
    }
  }

  /// Lets go of everything, for good.
  Future<void> dispose() async {
    await disconnect();
    await _incoming.close();
    await _states.close();
  }
}
