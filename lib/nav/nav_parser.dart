import 'nav_notification.dart';
import 'nav_state.dart';
import 'nav_text.dart';

/// Reads a [NavNotification] into a [NavState] (docs/NAV.md).
///
/// There are two shapes of Google Maps' notification, and this reads either: the
/// numbers are taken from where Google puts them as numbers (the progress and the
/// distance to the turn) and otherwise out of its text. A figure that cannot be
/// read is null and Google's own words are kept to show instead.
class NavParser {
  const NavParser({this.units});

  /// Units of distance to read in addition to the built-in ones, by their
  /// lower-case abbreviation, in metres (see [NavText.distanceUnits]).
  final Map<String, double>? units;

  /// What [notification] says, received at [now] (the phone's own clock, which
  /// is also the clock the ETA's time of day is read against).
  NavState parse(NavNotification notification, DateTime now) {
    final n = notification;
    final title = _nonEmpty(_clean(n.title));
    final text = _nonEmpty(_clean(n.text));
    final subText = _nonEmpty(_clean(n.subText));
    final critical = _clean(n.shortCriticalText);

    final shape = _isProgress(n) ? NavShape.progress : NavShape.classic;

    // A state with no turn in it has no picture. The notification then says
    // `Starting navigation…`, with nothing under it (no sub text at all), or
    // `Rerouting...`, with an ETA that has no time in it (`Arrive ` on Maps 25.33,
    // an empty sub text on 26.42). Neither is read by its words, which are in the
    // phone's language: a sub text that is there, empty or not, is a reroute.
    if (n.arrow == null) {
      final hasEta = subText != null && NavText.hasDigit(subText);
      if (!hasEta) {
        return NavState(
          phase: n.subText == null ? NavPhase.starting : NavPhase.rerouting,
          receivedAt: now,
          shape: shape,
          message: title ?? text,
        );
      }
    }

    String? distanceText;
    double? distanceM;
    String? instruction;
    double? leftM;
    Duration? timeLeft;
    String? etaText;
    DateTime? eta;
    var imperial = false;

    if (shape == NavShape.progress) {
      // `650 m · Turn right at ...`: the distance first, then the instruction.
      // The distance on its own is also in the short critical text, which is
      // trusted when it is there.
      final split = title == null ? null : _splitLeadingDistance(title);
      if (critical != null && critical.isNotEmpty) {
        distanceText = critical;
        distanceM = NavText.distanceMetres(critical, units: units);
        // Without understanding the unit: the title begins with the same text.
        instruction = (title == null ? null : _after(title, critical)) ?? title;
      } else if (split != null) {
        distanceText = split.$1;
        distanceM = NavText.distanceMetres(split.$1, units: units);
        instruction = split.$2;
      } else {
        instruction = title;
      }
      final max = n.progressMax ?? 0;
      if (max > 0) {
        leftM = (max - (n.progress ?? 0)).clamp(0, max).toDouble();
      }
      final clock = subText == null ? null : NavText.clock(subText);
      if (clock != null) {
        etaText = clock.text;
        eta = _timeOfDay(now, clock.hour, clock.minute);
      }
    } else {
      // The distance alone in the title, the street in the text.
      if (title != null && title.isNotEmpty) {
        distanceText = title;
        distanceM = NavText.distanceMetres(title, units: units);
      }
      instruction = text;
      // `28 min · 6.7 km · 9:25 PM ETA`: told apart by what each part is, not by
      // where it is.
      for (final part
          in subText == null ? <String>[] : NavText.parts(subText)) {
        final metres = NavText.distanceMetres(part, units: units);
        if (metres != null) {
          leftM = metres;
          imperial |= NavText.isImperial(part);
          continue;
        }
        final clock = NavText.clock(part);
        if (clock != null) {
          etaText = clock.text;
          eta = _timeOfDay(now, clock.hour, clock.minute);
          continue;
        }
        timeLeft ??= NavText.duration(part);
      }
    }

    // "0 m" is not a distance to count down to. Maps writes it beside "Head east" and
    // "towards ..." (there is nothing to turn at), and at the turn itself. The HUD
    // has no figure to show either way: a turn with none puts the dot at the
    // junction, which is also how it reads the progress shape, where Maps drops the
    // distance in the last metres. (Seen on a real phone, Maps 26.42: "0 M" beside a
    // straight arrow.)
    if (distanceM != null && distanceM <= 0) {
      imperial |= distanceText != null && NavText.isImperial(distanceText);
      distanceText = null;
      distanceM = null;
    }

    var derived = false;
    if (timeLeft == null && eta != null) {
      timeLeft = eta.difference(now);
      if (timeLeft.isNegative) timeLeft = Duration.zero;
      derived = true;
    }

    return NavState(
      phase: NavPhase.guiding,
      receivedAt: now,
      shape: shape,
      instruction: instruction,
      distanceText: distanceText,
      distanceToTurnM: distanceM,
      arrow: n.arrow,
      distanceLeftM: leftM,
      timeLeft: timeLeft,
      timeLeftIsDerived: derived,
      eta: eta,
      etaText: etaText,
      imperial:
          imperial ||
          (distanceText != null && NavText.isImperial(distanceText)),
    );
  }

  static bool _isProgress(NavNotification n) =>
      (n.progressMax ?? 0) > 0 ||
      (n.shortCriticalText != null) ||
      (n.template?.contains('ProgressStyle') ?? false);

  /// Display text: no-break spaces made ordinary and the ends trimmed. An empty
  /// string stays an empty string (an empty short critical text means there is
  /// no distance), and null stays null.
  static String? _clean(String? s) =>
      s?.replaceAll(RegExp('[\u00A0\u202F]'), ' ').trim();

  static String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;

  static final _leading = RegExp(r'^(.*?)\s*·\s*(.+)$');

  /// `650 m · Turn right ...` as (`650 m`, `Turn right ...`), when the first
  /// part is a distance.
  (String, String)? _splitLeadingDistance(String title) {
    final match = _leading.firstMatch(title);
    if (match == null) return null;
    final first = match.group(1)!.trim();
    if (NavText.distanceMetres(first, units: units) == null) return null;
    return (first, match.group(2)!.trim());
  }

  /// What follows [lead] at the start of [text], past the separator, or null if
  /// [text] does not start with it or nothing follows.
  static String? _after(String text, String lead) {
    if (!text.startsWith(lead)) return null;
    final rest = text
        .substring(lead.length)
        .replaceFirst(RegExp(r'^[\s·•|]+'), '');
    return rest.isEmpty ? null : rest;
  }

  /// The next time the clock shows [hour]:[minute] after a little before [now]:
  /// an ETA is ahead, so a time that has just gone is this minute's rounding and
  /// one well past is tomorrow's.
  static DateTime _timeOfDay(DateTime now, int hour, int minute) {
    var t = DateTime(now.year, now.month, now.day, hour, minute);
    if (t.isBefore(now.subtract(const Duration(minutes: 5)))) {
      t = t.add(const Duration(days: 1));
    }
    return t;
  }
}
