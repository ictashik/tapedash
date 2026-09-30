/// Somewhere to write a recorded session, for the hardware handoff (CLAUDE.md
/// 11): the real one writes a file on the phone, a test keeps it in memory.
abstract interface class SessionSink {
  /// Saves [text] as [name], replacing what was saved under that name before.
  Future<void> save(String name, String text);
}

/// A [SessionSink] that keeps what it is given, for tests.
class MemorySessionSink implements SessionSink {
  final Map<String, String> files = {};

  @override
  Future<void> save(String name, String text) async => files[name] = text;
}
