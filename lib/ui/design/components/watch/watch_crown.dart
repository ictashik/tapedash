import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../icons/icons.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/status_strip.dart';
import '../status_strip.dart';
import 'watch_face.dart';

/// The crown of the watch face (DESIGN.md 16.3): the link glyphs at 12 o'clock
/// where the circle is wide enough for them, and a warm glyph beside them when the
/// watch is hot. Glyphs only: the Parked captions of the phone's strip would not
/// fit the chord, and the faces say what they mean in words where it matters.
class WatchCrown extends StatelessWidget {
  const WatchCrown({
    super.key,
    required this.face,
    required this.gpsHasFix,
    this.adapter,
    this.hot,
  });

  final WatchFace face;

  /// The adapter link, or null for a drive on the GPS alone.
  final ValueListenable<AdapterLinkState>? adapter;
  final ValueListenable<bool> gpsHasFix;

  /// The watch is hot (DESIGN.md 16.9).
  final ValueListenable<bool>? hot;

  static const ValueListenable<double> _noCaptions =
      AlwaysStoppedAnimation<double>(0);

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return SizedBox.square(
      dimension: face.diameter,
      child: Stack(
        children: [
          Positioned(
            top: face.crownY - TapeStatusStrip.glyphSize / 2,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusStripLeft(
                    adapter: adapter,
                    gpsHasFix: gpsHasFix,
                    parkedShare: _noCaptions,
                  ),
                  if (hot != null)
                    ValueListenableBuilder<bool>(
                      valueListenable: hot!,
                      builder: (context, isHot, _) => isHot
                          ? Padding(
                              padding: const EdgeInsets.only(
                                left: TapeStatusStrip.gap * 2,
                              ),
                              child: TapeIconView(
                                TapeIcon.phoneHot,
                                size: TapeStatusStrip.glyphSize,
                                color: palette.caution,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
