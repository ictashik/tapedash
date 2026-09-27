import '../../core/scheduler.dart';
import '../elm327/elm327_client.dart';
import '../elm327/elm327_failure.dart';
import 'dtc.dart';

/// What reading the fault codes found.
class DtcReadResult {
  const DtcReadResult({
    this.stored = const [],
    this.pending = const [],
    this.failure,
  });

  /// Codes the ECU has stored: Mode 03. These are what lights the check-engine
  /// light.
  final List<Dtc> stored;

  /// Codes that have been seen once and are not yet stored: Mode 07.
  final List<Dtc> pending;

  /// Set if either could not be read; the other may still be there.
  final Elm327Failure? failure;

  bool get ok => failure == null;
}

/// What became of a request to clear the codes.
enum DtcClearOutcome {
  /// The ECU said 44: it has cleared them.
  cleared,

  /// The car is moving, or its speed is not known, so the request was not
  /// sent (CLAUDE.md 8.10). The ECU was not asked.
  notStationary,

  /// The ECU said no: `7F 04 22`, conditions not correct, as most do with the
  /// engine running.
  refusedByEcu,

  /// There was no usable answer.
  failed,
}

/// Reads and clears fault codes (CLAUDE.md 8.10): Mode 03 for the stored ones,
/// 07 for the pending ones, and 04 to clear them.
///
/// Its requests go through the same [Elm327Client] as the poller's, one at a
/// time, so a read waits for at most the request in flight.
class DtcService {
  DtcService({
    required this.client,
    required this.scheduler,
    required this.isCan,
    required this.isStationary,
  });

  final Elm327Client client;
  final Scheduler scheduler;

  /// Whether the car is on CAN, which decides how a message is laid out.
  final bool isCan;

  /// Whether the car is known to be at a standstill. Clearing is only allowed
  /// then, and not when the speed is unknown.
  final bool Function() isStationary;

  /// Reads the stored codes and then the pending ones.
  void read(void Function(DtcReadResult result) done) {
    _readMode(0x03, (stored, storedFailure) {
      _readMode(0x07, (pending, pendingFailure) {
        done(
          DtcReadResult(
            stored: stored ?? const [],
            pending: pending ?? const [],
            failure: storedFailure ?? pendingFailure,
          ),
        );
      });
    });
  }

  void _readMode(
    int mode,
    void Function(List<Dtc>? codes, Elm327Failure? failure) done,
  ) {
    // No count digit: every ECU that has codes answers, and the adapter must
    // wait for all of them.
    client.request(
      [mode],
      (reply) {
        if (!reply.ok) return done(null, reply.failure);
        final codes = DtcDecoder.decodeAll(
          reply.messages,
          reply: mode + 0x40,
          isCan: isCan,
        );
        // Only a negative answer, 7F: the ECU will not say.
        done(codes, codes == null ? Elm327Failure.noData : null);
      },
      acceptPrefixes: [
        [mode + 0x40],
        [0x7F, mode],
      ],
    );
  }

  /// Clears the codes, if the car is standing still.
  void clear(void Function(DtcClearOutcome outcome) done) {
    if (!isStationary()) {
      // Never call back from inside the call that asked.
      scheduler.runAfter(
        Duration.zero,
        () => done(DtcClearOutcome.notStationary),
      );
      return;
    }
    client.request(
      [0x04],
      (reply) {
        if (!reply.ok) return done(DtcClearOutcome.failed);
        for (final message in reply.messages) {
          if (message.isNotEmpty && message.first == 0x44) {
            return done(DtcClearOutcome.cleared);
          }
          // 7F, the service, and why: 22 is conditions not correct.
          if (message.length >= 3 && message[0] == 0x7F && message[1] == 0x04) {
            return done(DtcClearOutcome.refusedByEcu);
          }
        }
        done(DtcClearOutcome.failed);
      },
      acceptPrefixes: const [
        [0x44],
        [0x7F, 0x04],
      ],
    );
  }
}
