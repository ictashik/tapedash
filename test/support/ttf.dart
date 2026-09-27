import 'dart:io';
import 'dart:typed_data';

/// A minimal reader of TrueType files: enough to say which characters a font
/// has and what its variation axes are, so a test can check the bundled fonts
/// against the design without drawing anything.
class TtfFile {
  TtfFile(this._bytes) : _data = ByteData.sublistView(_bytes) {
    final tableCount = _data.getUint16(4);
    for (var i = 0; i < tableCount; i++) {
      final record = 12 + i * 16;
      final tag = String.fromCharCodes(_bytes.sublist(record, record + 4));
      _tables[tag] = _data.getUint32(record + 8);
    }
  }

  factory TtfFile.read(String path) =>
      TtfFile(Uint8List.fromList(File(path).readAsBytesSync()));

  final Uint8List _bytes;
  final ByteData _data;
  final Map<String, int> _tables = {};

  bool hasTable(String tag) => _tables.containsKey(tag);

  /// The code points the font has a glyph for.
  late final Set<int> codePoints = _readCmap();

  /// The variation axes, by tag: (minimum, default, maximum). Empty for a font
  /// that is not variable.
  late final Map<String, (double, double, double)> axes = _readAxes();

  Set<int> _readCmap() {
    final table = _tables['cmap'];
    if (table == null) return const {};
    final result = <int>{};
    final count = _data.getUint16(table + 2);
    for (var i = 0; i < count; i++) {
      final record = table + 4 + i * 8;
      final subtable = table + _data.getUint32(record + 4);
      switch (_data.getUint16(subtable)) {
        case 4:
          _readFormat4(subtable, result);
        case 12:
          _readFormat12(subtable, result);
      }
    }
    return result;
  }

  void _readFormat4(int at, Set<int> into) {
    final segments = _data.getUint16(at + 6) ~/ 2;
    final ends = at + 14;
    final starts = ends + segments * 2 + 2;
    final deltas = starts + segments * 2;
    final offsets = deltas + segments * 2;
    for (var s = 0; s < segments; s++) {
      final end = _data.getUint16(ends + s * 2);
      final start = _data.getUint16(starts + s * 2);
      final delta = _data.getInt16(deltas + s * 2);
      final offset = _data.getUint16(offsets + s * 2);
      for (var c = start; c <= end && c < 0xFFFF; c++) {
        int glyph;
        if (offset == 0) {
          glyph = (c + delta) & 0xFFFF;
        } else {
          final at = offsets + s * 2 + offset + (c - start) * 2;
          glyph = _data.getUint16(at);
          if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
        }
        if (glyph != 0) into.add(c);
      }
    }
  }

  void _readFormat12(int at, Set<int> into) {
    final groups = _data.getUint32(at + 12);
    for (var g = 0; g < groups; g++) {
      final group = at + 16 + g * 12;
      final start = _data.getUint32(group);
      final end = _data.getUint32(group + 4);
      final glyph = _data.getUint32(group + 8);
      if (glyph == 0) continue;
      for (var c = start; c <= end; c++) {
        into.add(c);
      }
    }
  }

  Map<String, (double, double, double)> _readAxes() {
    final table = _tables['fvar'];
    if (table == null) return const {};
    final axesOffset = _data.getUint16(table + 4);
    final count = _data.getUint16(table + 8);
    final size = _data.getUint16(table + 10);
    final result = <String, (double, double, double)>{};
    for (var i = 0; i < count; i++) {
      final at = table + axesOffset + i * size;
      final tag = String.fromCharCodes(_bytes.sublist(at, at + 4));
      double fixed(int o) => _data.getInt32(at + o) / 65536;
      result[tag] = (fixed(4), fixed(8), fixed(12));
    }
    return result;
  }

  /// The English name-table string with the given [id], or null.
  String? name(int id) {
    final table = _tables['name'];
    if (table == null) return null;
    final count = _data.getUint16(table + 2);
    final strings = table + _data.getUint16(table + 4);
    for (var i = 0; i < count; i++) {
      final record = table + 6 + i * 12;
      final platform = _data.getUint16(record);
      final nameId = _data.getUint16(record + 6);
      if (nameId != id || (platform != 3 && platform != 1)) continue;
      final length = _data.getUint16(record + 8);
      final offset = strings + _data.getUint16(record + 10);
      if (platform == 3) {
        final units = [
          for (var k = 0; k < length; k += 2) _data.getUint16(offset + k),
        ];
        return String.fromCharCodes(units);
      }
      return String.fromCharCodes(_bytes.sublist(offset, offset + length));
    }
    return null;
  }
}
