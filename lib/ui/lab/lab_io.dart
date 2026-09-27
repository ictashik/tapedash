import 'dart:io';
import 'dart:typed_data';

/// The Design Lab's own small file access, for "capture all" (DESIGN.md 13.2).
///
/// This is the one place under `lib/ui/` that touches `dart:io` directly: a dev
/// tool, not the product, and it never ships data anywhere (CLAUDE.md 1). It is
/// a stand-in for a proper app-storage path from the device channel, noted in
/// docs/DECISIONS.md.
abstract final class LabIo {
  static Future<String> tempDirectory() async {
    final dir = Directory('${Directory.systemTemp.path}/tapedash-lab');
    await dir.create(recursive: true);
    return dir.path;
  }

  static Future<File> writeFile(String dir, String filename, Uint8List bytes) =>
      File('$dir/$filename.png').writeAsBytes(bytes);
}
