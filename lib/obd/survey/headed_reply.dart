/// One ECU's message, put back together from the frames the adapter printed
/// with headers on.
class HeadedMessage {
  const HeadedMessage({
    required this.id,
    required this.payload,
    required this.complete,
  });

  /// The ID the frames came from: `7E8`, or `18DAF110` on 29-bit CAN.
  final String id;

  /// The message bytes, without the CAN header or the ISO-TP framing. If
  /// [complete] is false, only the part that arrived.
  final List<int> payload;

  /// False if the message is longer than what arrived: a first frame with no,
  /// or not enough, frames after it.
  final bool complete;

  @override
  String toString() =>
      'HeadedMessage($id, ${payload.length} bytes${complete ? '' : ', cut'})';
}

/// Reads an adapter's lines when headers are on (`ATH1`): every line is one CAN
/// frame, its ID and then its eight bytes, and the ISO 15765-2 framing is left
/// for us to take off (ELM327 datasheet, "Printing of headers").
///
/// This is how a survey tells the ECUs apart. It is tolerant of spaces, and
/// takes a 3-digit ID as 11-bit CAN and an 8-digit one as 29-bit CAN, which the
/// length of a line settles, since the data is always whole bytes. A line that
/// is not a frame (the numbered lines an adapter prints with headers off, or
/// noise) is counted in [unreadable] and otherwise ignored.
///
/// **Unverified against a real adapter.** The format follows the datasheet and
/// what other tools document; the simulator produces it, and a real adapter's
/// first survey will say whether it is right. A survey keeps the raw text
/// whatever this makes of it.
abstract final class HeadedReply {
  /// The messages in [lines], in the order each ECU first appears, and the
  /// lines that were not frames.
  static ({List<HeadedMessage> messages, List<String> unreadable}) parse(
    List<String> lines,
  ) {
    final unreadable = <String>[];
    final done = <HeadedMessage>[];
    // The message each ID is putting together: its bytes so far, how many it
    // will have, and the sequence number it expects next.
    final open = <String, _Assembly>{};
    final order = <String>[];
    final built = <String, List<HeadedMessage>>{};

    void close(String id) {
      final a = open.remove(id);
      if (a == null) return;
      final complete = a.bytes.length >= a.total;
      (built[id] ??= []).add(
        HeadedMessage(
          id: id,
          payload: complete ? a.bytes.sublist(0, a.total) : a.bytes,
          complete: complete && !a.gap,
        ),
      );
    }

    for (final line in lines) {
      final frame = _frame(line);
      if (frame == null) {
        unreadable.add(line);
        continue;
      }
      final (id, data) = frame;
      if (!order.contains(id)) order.add(id);
      final pci = data.first >> 4;
      switch (pci) {
        case 0:
          final length = data.first & 0xF;
          close(id);
          (built[id] ??= []).add(
            HeadedMessage(
              id: id,
              payload: data.sublist(
                1,
                length + 1 > data.length ? data.length : length + 1,
              ),
              complete: length + 1 <= data.length,
            ),
          );
        case 1:
          if (data.length < 2) {
            unreadable.add(line);
            break;
          }
          close(id);
          open[id] = _Assembly(
            total: ((data.first & 0xF) << 8) | data[1],
            bytes: data.sublist(2),
          );
        case 2:
          final a = open[id];
          if (a == null) {
            unreadable.add(line);
            break;
          }
          if ((data.first & 0xF) != a.next) a.gap = true;
          a.next = (a.next + 1) & 0xF;
          a.bytes.addAll(data.sublist(1));
        default:
          // Flow control from the adapter, or something else: not a message.
          unreadable.add(line);
      }
    }
    for (final id in open.keys.toList()) {
      close(id);
    }
    for (final id in order) {
      done.addAll(built[id] ?? const []);
    }
    return (messages: done, unreadable: unreadable);
  }

  /// A line as its ID and bytes, or null if it is not a frame.
  static (String, List<int>)? _frame(String line) {
    final compact = line.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(compact)) return null;
    // 3 digits of ID and whole bytes: odd. 8 digits and whole bytes: even.
    final idLength = compact.length.isOdd ? 3 : 8;
    if (compact.length < idLength + 2) return null;
    final id = compact.substring(0, idLength);
    final hex = compact.substring(idLength);
    return (
      id,
      [
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ],
    );
  }
}

class _Assembly {
  _Assembly({required this.total, required this.bytes});

  final int total;
  final List<int> bytes;
  int next = 1;
  bool gap = false;
}
