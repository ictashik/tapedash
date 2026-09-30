import 'dart:io';

import '../obd/transport/session_sink.dart';
import 'device_features.dart';

/// Writes recorded sessions to a folder on the phone (CLAUDE.md 11): the app's own
/// external files folder, in `recordings/`, which is reachable over USB with
/// `adb pull /sdcard/Android/data/<package>/files/recordings/` and needs no
/// storage permission. Nothing leaves the phone by itself.
class FileSessionSink implements SessionSink {
  FileSessionSink(this._device);

  final DeviceFeatures _device;

  /// Where the recordings are, once known.
  String? directory;

  @override
  Future<void> save(String name, String text) async {
    final base = await _device.externalFilesDirectory();
    if (base == null) {
      throw const FileSystemException('The phone has no folder to write to');
    }
    final dir = Directory('$base/recordings');
    await dir.create(recursive: true);
    directory = dir.path;
    // Written to a temporary name and then renamed, so that a phone that dies
    // mid-write leaves the last good copy, not half a file.
    final target = File('${dir.path}/$name');
    final temp = File('${target.path}.part');
    await temp.writeAsString(text, flush: true);
    await temp.rename(target.path);
  }
}
