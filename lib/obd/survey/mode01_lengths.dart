/// How many data bytes the answer to each standard Mode 01 PID has (SAE J1979),
/// so that an answer to several PIDs can be walked through.
///
/// Only the lengths are here. What the bytes mean is `lib/obd/pids/pid.dart`'s
/// business for the PIDs TapeDash reads, and for the rest it is for whoever
/// reads a survey, with the standard beside them: no formula is guessed. PIDs
/// above 63 are left out, since a wrong length would put every PID after it out
/// of step; they are asked for one at a time.
abstract final class Mode01Lengths {
  static const Map<int, int> _lengths = {
    0x00: 4, 0x01: 4, 0x02: 2, 0x03: 2, 0x04: 1, 0x05: 1, 0x06: 1, //
    0x07: 1, 0x08: 1, 0x09: 1, 0x0A: 1, 0x0B: 1, 0x0C: 2, 0x0D: 1, //
    0x0E: 1, 0x0F: 1, 0x10: 2, 0x11: 1, 0x12: 1, 0x13: 1, 0x14: 2, //
    0x15: 2, 0x16: 2, 0x17: 2, 0x18: 2, 0x19: 2, 0x1A: 2, 0x1B: 2, //
    0x1C: 1, 0x1D: 1, 0x1E: 1, 0x1F: 2, 0x20: 4, 0x21: 2, 0x22: 2, //
    0x23: 2, 0x24: 4, 0x25: 4, 0x26: 4, 0x27: 4, 0x28: 4, 0x29: 4, //
    0x2A: 4, 0x2B: 4, 0x2C: 1, 0x2D: 1, 0x2E: 1, 0x2F: 1, 0x30: 1, //
    0x31: 2, 0x32: 2, 0x33: 1, 0x34: 4, 0x35: 4, 0x36: 4, 0x37: 4, //
    0x38: 4, 0x39: 4, 0x3A: 4, 0x3B: 4, 0x3C: 2, 0x3D: 2, 0x3E: 2, //
    0x3F: 2, 0x40: 4, 0x41: 4, 0x42: 2, 0x43: 2, 0x44: 2, 0x45: 1, //
    0x46: 1, 0x47: 1, 0x48: 1, 0x49: 1, 0x4A: 1, 0x4B: 1, 0x4C: 1, //
    0x4D: 2, 0x4E: 2, 0x4F: 4, 0x50: 4, 0x51: 1, 0x52: 1, 0x53: 2, //
    0x54: 2, 0x55: 2, 0x56: 2, 0x57: 2, 0x58: 2, 0x59: 2, 0x5A: 1, //
    0x5B: 1, 0x5C: 1, 0x5D: 2, 0x5E: 2, 0x5F: 1, 0x60: 4, 0x61: 1, //
    0x62: 1, 0x63: 2,
  };

  /// The data bytes of [pid]'s answer, or null if the length is not known here.
  static int? of(int pid) => _lengths[pid];

  /// Whether [pid] is one of the PIDs whose data is a mask of the next 32: 00,
  /// 20, 40...
  static bool isSupportMask(int pid) => pid % 0x20 == 0;

  /// The values in a Mode 01 answer ([message] starts with `41`), as PID and
  /// data, in the order they appear, and whether all of it could be read: it is
  /// not if a PID's length is not known or the data is cut short.
  static ({List<(int, List<int>)> values, bool complete}) walk(
    List<int> message,
  ) {
    final values = <(int, List<int>)>[];
    if (message.length < 2 || message.first != 0x41) {
      return (values: values, complete: false);
    }
    var i = 1;
    while (i < message.length) {
      final pid = message[i];
      final length = of(pid);
      if (length == null || i + 1 + length > message.length) {
        return (values: values, complete: false);
      }
      values.add((pid, message.sublist(i + 1, i + 1 + length)));
      i += 1 + length;
    }
    return (values: values, complete: true);
  }
}
