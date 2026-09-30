/// A byte pipe to an adapter that the phone's own radio makes, whichever radio it
/// is: what Bluetooth Classic and BLE both give the app through a platform channel
/// (CLAUDE.md 5). The channels themselves are in `lib/platform/`; this is the only
/// thing the OBD layer knows of them, so it stays pure Dart and is tested against a
/// fake.
abstract interface class NativeLink {
  /// Opens the pipe to the adapter. Completes when it is up, and fails with a
  /// [NativeLinkException] if it cannot be.
  Future<void> open();

  /// Closes the pipe. Safe to call when it is not up.
  Future<void> close();

  /// Sends [text] as it is. Fails with a [NativeLinkException] if the pipe is
  /// not up.
  Future<void> send(String text);

  /// What the adapter sends, in the pieces it arrives in. A broadcast stream.
  Stream<String> get incoming;

  /// Fires when the pipe drops underneath the app: the adapter was unplugged, went
  /// out of range or switched off. It does not fire for a [close].
  Stream<void> get lost;
}

/// Why a [NativeLink] could not do what it was asked.
enum NativeLinkProblem {
  /// The user has not allowed the app to use Bluetooth (or find nearby devices).
  permissionDenied,

  /// Bluetooth is switched off on the phone.
  radioOff,

  /// The phone has no such radio.
  unsupported,

  /// The adapter was not found or would not accept the connection.
  connectFailed,

  /// The pipe is not up.
  notConnected,

  /// Anything else the platform reported.
  other,
}

class NativeLinkException implements Exception {
  const NativeLinkException(this.problem, [this.message]);

  final NativeLinkProblem problem;
  final String? message;

  @override
  String toString() => message == null
      ? 'NativeLinkException(${problem.name})'
      : 'NativeLinkException(${problem.name}): $message';
}
