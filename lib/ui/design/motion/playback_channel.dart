import 'package:flutter/foundation.dart';

import '../../../coach/sample_events.dart';
import '../../../trips/trip_playback.dart';
import '../tokens/motion_tokens.dart';
import 'numeral_source.dart';
import 'trip_player.dart';

/// One reading of a replay as a [NumeralSource], for the replay's numerals and bars:
/// the speed, the ₹ so far, the distance. It is what the moment of the player's
/// [TripPlayer.frame] says, read when it is asked, so it is always current, and it
/// tells its painters when the play head moves. There is no smoothing and no stale
/// data: a replay has none of either.
///
/// A channel the trip did not record (NaN) has no value to show.
///
/// With a [step] the value is rounded to a multiple of it: a readout that changes
/// every frame (the ₹ so far) would otherwise be part-way through a roll nearly all
/// of the time, and a replay's numbers, like a parked screen's, are set on whole
/// digits (DESIGN.md 5.6).
class PlaybackChannel extends ChangeNotifier implements NumeralSource {
  PlaybackChannel(this.player, this.read, {this.step = 0}) {
    player.addListener(notifyListeners);
  }

  final TripPlayer player;
  final double Function(PlaybackFrame frame) read;

  /// The grain of the value, or 0 for none.
  final double step;

  @override
  double get value {
    final v = read(player.frame);
    if (v.isNaN) return 0;
    return step > 0 ? (v / step).roundToDouble() * step : v;
  }

  @override
  double get staleness => 0;

  @override
  bool get hasValue => !read(player.frame).isNaN;

  @override
  void dispose() {
    player.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Which of a trip's marked moments (hard acceleration, hard braking, a long idle)
/// the replay has just passed: [current] is it for [TapeReplay.eventHoldSeconds]
/// (more at 2 and 3 times, so that it is as long to the eye), and null after. It
/// tells its listeners only when that changes.
class ReplayEvents extends ChangeNotifier {
  ReplayEvents({required this.player, required List<SampleEvent> events})
    : _events = events,
      _times = [for (final e in events) player.playback.timeOfSample(e.index)] {
    player.addListener(_update);
    _update();
  }

  final TripPlayer player;
  final List<SampleEvent> _events;
  final List<double> _times;

  SampleEventType? _current;
  int _index = -1;

  /// The moment being shown, or null.
  SampleEventType? get current => _current;

  void _update() {
    final t = player.seconds;
    // The last event at or before t.
    var lo = 0, hi = _events.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_times[mid] <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final i = lo - 1;
    SampleEventType? next;
    if (i >= 0 && t - _times[i] <= TapeReplay.eventHoldSeconds * player.rate) {
      next = _events[i].type;
    }
    if (next == _current && (next == null || i == _index)) return;
    _current = next;
    _index = next == null ? -1 : i;
    notifyListeners();
  }

  @override
  void dispose() {
    player.removeListener(_update);
    super.dispose();
  }
}
