import 'dart:convert';
import 'dart:io';

import 'device_features.dart';

/// The folder the exchange files live in (docs/EXCHANGE.md 4): the app's own external
/// files folder, `exchange/`, with `outbox/`, `inbox/` and `done/` in it and a
/// `result.json`. It needs no permission, and adb reaches it
/// (`/sdcard/Android/data/<package>/files/exchange`).
///
/// Nothing leaves the phone by itself: a file in `outbox/` stays there until a
/// person or adb takes it.
class ExchangeFiles {
  /// Files in [rootDirectory] (a test gives a temporary directory), or in the folder
  /// the phone gives through [device].
  ExchangeFiles({this.rootDirectory, this.device});

  /// Where the files are kept, when it is not the phone's own folder.
  final Directory? rootDirectory;
  final DeviceFeatures? device;
  Directory? _resolved;

  /// The file extensions an import takes.
  static const List<String> extensions = ['.tdx', '.tdx.gz'];

  /// The folder, made if it is not there; null if the phone has none.
  Future<Directory?> root() async {
    final known = _resolved;
    if (known != null) return known;
    var base = rootDirectory;
    if (base == null) {
      final path = await device?.externalFilesDirectory();
      if (path == null) return null;
      base = Directory('$path/exchange');
    }
    for (final sub in ['outbox', 'inbox', 'done']) {
      await Directory('${base.path}/$sub').create(recursive: true);
    }
    return _resolved = base;
  }

  Future<Directory?> _sub(String name) async {
    final r = await root();
    return r == null ? null : Directory('${r.path}/$name');
  }

  /// Where a person or adb finds an export, for the screen to say.
  Future<String?> get outboxPath async => (await _sub('outbox'))?.path;

  /// The files waiting in `inbox/`, oldest name first.
  Future<List<File>> inbox() async {
    final dir = await _sub('inbox');
    if (dir == null || !dir.existsSync()) return const [];
    final files = [
      for (final e in dir.listSync())
        if (e is File && _isExchangeFile(e.path)) e,
    ]..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static bool _isExchangeFile(String path) {
    final lower = path.toLowerCase();
    return extensions.any(lower.endsWith);
  }

  /// A file to write in `outbox/`, called [name]. An existing one of the same name
  /// is not overwritten: a number is added.
  Future<File?> newOutboxFile(String name) async {
    final dir = await _sub('outbox');
    if (dir == null) return null;
    return _free(dir, name);
  }

  /// Moves a file that has been imported to `done/`, keeping it.
  Future<void> markDone(File file) async {
    final dir = await _sub('done');
    if (dir == null) return;
    final name = file.uri.pathSegments.last;
    await file.rename(_free(dir, name).path);
  }

  /// Says what the last export or import did, for a script to read.
  Future<void> writeResult(Map<String, Object?> json) async {
    final r = await root();
    if (r == null) return;
    final file = File('${r.path}/result.json');
    final part = File('${file.path}.part');
    await part.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    await part.rename(file.path);
  }

  /// [name] in [dir], or `name-2`, `name-3` and so on if it is taken.
  static File _free(Directory dir, String name) {
    var target = File('${dir.path}/$name');
    var n = 2;
    final dot = name.indexOf('.');
    final stem = dot < 0 ? name : name.substring(0, dot);
    final ext = dot < 0 ? '' : name.substring(dot);
    while (target.existsSync()) {
      target = File('${dir.path}/$stem-${n++}$ext');
    }
    return target;
  }

  /// A file's name as an export gets it (docs/EXCHANGE.md 1):
  /// `tapedash-<what>-<yyyymmdd-hhmmss>-<phone|watch>.tdx[.gz]`.
  static String fileName({
    required String what,
    required DateTime at,
    required String kind,
    required bool gzip,
  }) {
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}';
    return 'tapedash-$what-$stamp-$kind.tdx${gzip ? '.gz' : ''}';
  }
}
