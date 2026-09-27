import '../elm327/elm327_client.dart';
import '../elm327/elm327_failure.dart';

/// One of an ECU's support replies: PID 00, 20, 40 and so on each answer with
/// four bytes, one bit for each of the next 32 PIDs (SAE J1979).
class PidSupport {
  const PidSupport(this.base, this.pids, {required this.nextRange});

  /// The PID that was asked: 0x00, 0x20, 0x40...
  final int base;

  /// The PIDs in `base + 1` to `base + 0x1F` that the ECU supports.
  final Set<int> pids;

  /// Whether the last bit is set: there is another range to ask about, at
  /// `base + 0x20`.
  final bool nextRange;

  /// The four data bytes of the reply to PID [base].
  static PidSupport decode(int base, List<int> data) {
    if (data.length != 4) {
      throw ArgumentError.value(data, 'data', 'a support reply has 4 bytes');
    }
    final mask = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
    final pids = <int>{};
    // The top bit is base + 1, and the bottom bit is base + 0x20, which is
    // not a PID of this range but the flag for the next.
    for (var bit = 0; bit < 31; bit++) {
      if (mask & (1 << (31 - bit)) != 0) pids.add(base + 1 + bit);
    }
    return PidSupport(base, pids, nextRange: mask & 1 != 0);
  }
}

/// What discovery found.
class DiscoveryResult {
  const DiscoveryResult({
    this.supported = const {},
    this.ecuCount = 0,
    this.failure,
    this.searched = false,
  });

  /// The Mode 01 PIDs the car answers: the union over every ECU that replied.
  /// The support PIDs themselves (00, 20, 40...) are not in it.
  final Set<int> supported;

  /// How many ECUs answered the first request.
  final int ecuCount;

  /// Set if the very first request got no answer.
  final Elm327Failure? failure;

  /// Whether the adapter searched for a protocol on the way.
  final bool searched;

  bool get ok => failure == null;
}

/// Asks the car which PIDs it supports (CLAUDE.md 8.2): PID 00 first, and then
/// each next range for as long as the last bit of a reply says there is one.
abstract final class PidDiscovery {
  /// The PID numbers that ask about a range.
  static const List<int> ranges = [0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0];

  /// Runs discovery on [client] and calls [done] with what it found.
  ///
  /// The first request is the one that may make the adapter search for a
  /// protocol, so it gets [firstTimeout]. A later range that gets no answer
  /// ends discovery with what it has.
  static void run(
    Elm327Client client,
    void Function(DiscoveryResult result) done, {
    Duration? firstTimeout,
  }) {
    final supported = <int>{};
    var ecuCount = 0;
    var searched = false;

    void ask(int base) {
      final first = base == 0x00;
      client.request(
        [0x01, base],
        (reply) {
          searched = searched || reply.searched;
          if (!reply.ok) {
            done(
              first
                  ? DiscoveryResult(failure: reply.failure, searched: searched)
                  : DiscoveryResult(
                      supported: supported,
                      ecuCount: ecuCount,
                      searched: searched,
                    ),
            );
            return;
          }
          var next = false;
          var answered = 0;
          for (final message in reply.messages) {
            if (message.length != 6) continue;
            answered++;
            final support = PidSupport.decode(base, message.sublist(2));
            supported.addAll(support.pids);
            next = next || support.nextRange;
          }
          if (first) ecuCount = answered;
          if (first && answered == 0) {
            done(
              DiscoveryResult(
                failure: Elm327Failure.garbled,
                searched: searched,
              ),
            );
            return;
          }
          final index = ranges.indexOf(base);
          if (next && index + 1 < ranges.length) {
            ask(ranges[index + 1]);
          } else {
            done(
              DiscoveryResult(
                supported: supported,
                ecuCount: ecuCount,
                searched: searched,
              ),
            );
          }
        },
        expectPrefix: [0x41, base],
        timeout: first ? firstTimeout : null,
      );
    }

    ask(0x00);
  }
}
