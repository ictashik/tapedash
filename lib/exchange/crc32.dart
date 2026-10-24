import 'dart:typed_data';

/// CRC-32 (IEEE 802.3, the polynomial 0xEDB88320): the checksum of gzip, zip and
/// PNG. The exchange file's footer carries one over everything before it
/// (docs/EXCHANGE.md 1), so a file that was cut short or damaged on its way is
/// refused whole.
class Crc32 {
  static final Uint32List _table = _makeTable();

  int _crc = 0xFFFFFFFF;

  static Uint32List _makeTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      table[n] = c;
    }
    return table;
  }

  /// Adds [bytes] to the checksum.
  void add(List<int> bytes) {
    var c = _crc;
    for (final b in bytes) {
      c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    _crc = c;
  }

  /// The checksum of everything added so far.
  int get value => (_crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;

  /// [value] as the eight lowercase hex digits the footer carries.
  String get hex => value.toRadixString(16).padLeft(8, '0');

  /// The checksum of [bytes] alone.
  static int of(List<int> bytes) => (Crc32()..add(bytes)).value;
}
