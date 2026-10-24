import 'dart:async';

import 'package:flutter/services.dart';

import '../nav/nav_notification.dart';

/// What the native listener tells the app about Google Maps' navigation
/// notification (docs/NAV.md).
sealed class NavEvent {
  const NavEvent();
}

/// Maps posted, or updated, its navigation notification.
class NavPosted extends NavEvent {
  const NavPosted(this.notification);
  final NavNotification notification;
}

/// Maps took its navigation notification away.
class NavRemoved extends NavEvent {
  const NavRemoved();
}

/// Android's Notification access was granted ([connected]) or taken away.
class NavLink extends NavEvent {
  const NavLink({required this.connected});
  final bool connected;
}

/// Where the navigation notification comes from: the phone's own listener, or a
/// fake in a test (CLAUDE.md 6).
abstract interface class NavSource {
  /// Whether TapeDash has been granted Notification access.
  Future<bool> hasAccess();

  /// Opens Android's screen for granting it. False if the phone has none.
  Future<bool> openAccessSettings();

  /// The version of Google Maps on the phone, or null if it is not there.
  Future<String?> mapsVersion();

  /// The navigation notification as it changes. **Listening is what starts the
  /// reading**: with no listener, the native side does not open a notification
  /// (`NavBridge.kt`), so a switch that is off reads nothing.
  Stream<NavEvent> events();
}

/// [NavSource] on the platform channels implemented by `NavChannel.kt`.
///
/// Unverified on a phone until the handoff (CLAUDE.md 11): the tests run against a
/// mocked channel, and it has been run on an Android 16 emulator against real
/// Google Maps.
class NativeNavSource implements NavSource {
  NativeNavSource({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel('tapedash/nav'),
      _events = events ?? const EventChannel('tapedash/nav/events');

  final MethodChannel _methods;
  final EventChannel _events;

  @override
  Future<bool> hasAccess() async {
    try {
      return await _methods.invokeMethod<bool>('access') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> openAccessSettings() async {
    try {
      return await _methods.invokeMethod<bool>('openAccessSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String?> mapsVersion() async {
    try {
      return await _methods.invokeMethod<String>('mapsVersion');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Stream<NavEvent> events() => _events
      .receiveBroadcastStream()
      .map(decode)
      .where((e) => e != null)
      .cast<NavEvent>();

  /// Reads one event of the channel; null for one it does not know.
  static NavEvent? decode(Object? message) {
    if (message is! Map) return null;
    return switch (message['event']) {
      'posted' => NavPosted(NavNotification.fromMap(message)),
      'removed' => const NavRemoved(),
      'connected' => const NavLink(connected: true),
      'disconnected' => const NavLink(connected: false),
      _ => null,
    };
  }
}

/// A [NavSource] that is told what to say, for tests and for a phone with no
/// listener.
class FakeNavSource implements NavSource {
  FakeNavSource({this.access = false, this.maps = '25.33.03'});

  bool access;

  /// The version of Maps there is, or null for none.
  String? maps;

  /// How many times the access screen was opened.
  int accessScreenOpened = 0;

  /// How many listeners the events have now, so a test can see that a switch that
  /// is off listens to nothing.
  int get listeners => _listeners;
  int _listeners = 0;

  late final StreamController<NavEvent> _controller =
      StreamController<NavEvent>.broadcast(
        onListen: () => _listeners++,
        onCancel: () => _listeners--,
      );

  /// What Maps does, as the listener would report it.
  void push(NavEvent event) => _controller.add(event);

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<bool> openAccessSettings() async {
    accessScreenOpened++;
    return true;
  }

  @override
  Future<String?> mapsVersion() async => maps;

  @override
  Stream<NavEvent> events() => _controller.stream;
}
