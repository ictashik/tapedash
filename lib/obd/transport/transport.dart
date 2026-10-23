/// Where a link to an adapter stands.
enum TransportStatus { disconnected, connecting, connected }

/// Why a link is not up, when it did not go down because the app said so.
enum TransportFailure {
  /// The adapter could not be reached: it is out of range or switched off, or
  /// the address is wrong.
  unreachable,

  /// The link was up and then dropped.
  lost,

  /// Something was written when there was no link.
  notConnected,

  /// A connection that was being made was cancelled by a disconnect.
  cancelled,
}

/// The state of a [Transport], and if it is disconnected against the app's
/// wishes, why.
class TransportState {
  const TransportState(this.status, {this.failure});

  /// Down because the app asked, or because it was never up.
  const TransportState.disconnected({this.failure})
    : status = TransportStatus.disconnected;

  static const TransportState connecting = TransportState(
    TransportStatus.connecting,
  );
  static const TransportState connected = TransportState(
    TransportStatus.connected,
  );

  final TransportStatus status;

  /// Set when [status] is disconnected and something went wrong.
  final TransportFailure? failure;

  bool get isConnected => status == TransportStatus.connected;

  @override
  bool operator ==(Object other) =>
      other is TransportState &&
      other.status == status &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(status, failure);

  @override
  String toString() =>
      failure == null ? status.name : '${status.name} (${failure!.name})';
}

/// A transport could not do what it was asked.
class TransportException implements Exception {
  const TransportException(this.failure, [this.message]);

  final TransportFailure failure;
  final String? message;

  @override
  String toString() => message == null
      ? 'TransportException(${failure.name})'
      : 'TransportException(${failure.name}): $message';
}

/// A transport that can say what is going on underneath it: which kind of socket
/// connected, a status code that came with a failure, the services an adapter
/// listed. It is for the connection log, which is how a link that will not come up
/// (and says nothing else) is understood afterwards. Plain text, one line a piece.
abstract interface class LinkDiagnostics {
  /// A broadcast stream of lines.
  Stream<String> get diagnostics;
}

/// The link to an ELM327 adapter (CLAUDE.md 6): text goes out, text comes back,
/// and the state of the link is reported. Everything above it deals in ELM327
/// strings; whether they travel by Bluetooth Classic, BLE, WiFi, from the
/// simulator or from a recording is the transport's business.
abstract interface class Transport {
  /// The state now.
  TransportState get currentState;

  /// Changes of state, as they happen. It is a broadcast stream.
  Stream<TransportState> get state;

  /// What the adapter sends, in the pieces it arrives in. A piece can end
  /// anywhere: half way through a line, or between the data and the prompt.
  /// It is a broadcast stream, so what arrives while nobody listens is lost, as
  /// it would be from a real link.
  Stream<String> get incoming;

  /// Opens the link. Completes when it is up, and fails with a
  /// [TransportException] if it cannot be.
  Future<void> connect();

  /// Closes the link. Safe to call when it is not up.
  Future<void> disconnect();

  /// Sends [data], exactly as given: a command has to end with `\r`. Fails with
  /// a [TransportException] if the link is not up.
  Future<void> write(String data);
}
