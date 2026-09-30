import 'adapter_config.dart';

/// What the connect flow asks about an adapter before it is used (DESIGN.md
/// 7.11), without touching a transport: whether its address is one the app may
/// talk to at all, and whether it answers.
abstract interface class AdapterChecker {
  /// Whether an adapter at [host] may be used: on a private network only
  /// (CLAUDE.md 4).
  bool allows(String host);

  /// Opens a link to [config] and closes it again, and says whether it opened.
  Future<bool> reachable(AdapterConfig config);
}
