import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tapedash/nav/nav_arrow.dart';
import 'package:tapedash/nav/nav_notification.dart';

/// A fixture arrow: a mask of the size the capture found, with nothing drawn.
/// The parser keeps an arrow and never reads its pixels.
NavArrow fixtureArrow(String id, {int width = 126, int height = 126}) =>
    NavArrow(
      id: id,
      width: width,
      height: height,
      alpha: Uint8List(width * height),
    );

/// One line of a fixture file: the notification, and when it was posted in
/// milliseconds from the first.
typedef FixtureRecord = ({
  int t,
  String event,
  NavNotification? notification,
  Map<String, Object?> raw,
});

/// The records of a navigation fixture (test/fixtures/nav/).
List<FixtureRecord> loadNavFixture(String name) {
  final lines = File('test/fixtures/nav/$name').readAsLinesSync();
  return [
    for (final line in lines)
      if (line.trim().isNotEmpty) _record(jsonDecode(line) as Map),
  ];
}

FixtureRecord _record(Map<Object?, Object?> raw) {
  final event = raw['event'] as String;
  return (
    t: raw['t'] as int,
    event: event,
    notification: event == 'posted'
        ? NavNotification.fromMap(raw, arrowFor: fixtureArrow)
        : null,
    raw: raw.cast<String, Object?>(),
  );
}
