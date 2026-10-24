import 'dart:typed_data';

import 'nav_arrow.dart';

/// What the native listener hands over for one navigation notification: the
/// fields of Google Maps' notification as they are, in Google's words, with
/// nothing read out of them (that is [NavParser]'s job).
///
/// This is also the wire format of the `tapedash/nav` channel
/// (`NavListenerService.kt`), and what `NavSimulator` produces. The fields are
/// those found in a capture of Google Maps 25.33 (docs/NAV.md).
class NavNotification {
  const NavNotification({
    this.title,
    this.text,
    this.subText,
    this.shortCriticalText,
    this.progress,
    this.progressMax,
    this.template,
    this.arrow,
  });

  /// `android.title`: the distance to the turn on its own (the classic shape),
  /// or the distance and the instruction (`650 m · Turn right ...`), or only an
  /// instruction, or a state (`Starting navigation…`, `Rerouting...`).
  final String? title;

  /// `android.text`: the street (`toward Vittal Mallya Rd`) in the classic
  /// shape; null in the other.
  final String? text;

  /// `android.subText`: time left, distance left and the ETA (classic), or only
  /// `Arrive 9:25 PM`.
  final String? subText;

  /// `android.shortCriticalText`: the distance to the turn alone (`650 m`), empty
  /// when there is none. Android 16's progress shape only.
  final String? shortCriticalText;

  /// `android.progress` and `android.progressMax`: metres along the route, and
  /// the route's length in metres. Android 16's progress shape only; both are 0
  /// in the classic one.
  final int? progress;
  final int? progressMax;

  /// `android.template`: `android.app.Notification$ProgressStyle` in the progress
  /// shape.
  final String? template;

  /// The manoeuvre's picture, null while there is none (`Rerouting...`).
  final NavArrow? arrow;

  /// The wire form of this notification. [sendArrowPixels] is false when the
  /// receiver already has this arrow.
  Map<String, Object?> toMap({bool sendArrowPixels = true}) => {
    'title': title,
    'text': text,
    'subText': subText,
    'shortCriticalText': shortCriticalText,
    'progress': progress,
    'progressMax': progressMax,
    'template': template,
    'arrow': arrow == null
        ? null
        : {
            'id': arrow!.id,
            'width': arrow!.width,
            'height': arrow!.height,
            if (sendArrowPixels) 'alpha': arrow!.alpha,
          },
  };

  /// Reads the wire form. [arrowFor] gives an arrow the receiver already holds
  /// when the message carries only its id.
  static NavNotification fromMap(
    Map<Object?, Object?> map, {
    NavArrow? Function(String id)? arrowFor,
  }) {
    NavArrow? arrow;
    final a = map['arrow'];
    if (a is Map) {
      final id = a['id'] as String?;
      final alpha = a['alpha'];
      final width = a['width'] as int?;
      final height = a['height'] as int?;
      if (id != null && alpha is Uint8List && width != null && height != null) {
        if (alpha.length == width * height) {
          arrow = NavArrow(id: id, width: width, height: height, alpha: alpha);
        }
      } else if (id != null) {
        arrow = arrowFor?.call(id);
      }
    }
    return NavNotification(
      title: map['title'] as String?,
      text: map['text'] as String?,
      subText: map['subText'] as String?,
      shortCriticalText: map['shortCriticalText'] as String?,
      progress: (map['progress'] as num?)?.toInt(),
      progressMax: (map['progressMax'] as num?)?.toInt(),
      template: map['template'] as String?,
      arrow: arrow,
    );
  }
}
