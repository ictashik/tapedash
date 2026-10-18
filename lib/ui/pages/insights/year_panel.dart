import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../insights/year_on_tape.dart';
import '../../../platform/image_sharer.dart';
import '../../design/components/controls/tape_button.dart';
import '../../design/components/controls/tape_segmented.dart';
import '../../design/components/insights/year_poster.dart';
import '../../design/icons/icons.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import 'insight_layout.dart';

/// What became of the last Share, for the page to say.
enum ShareStatus { idle, working, shared, failed }

/// Year on Tape (DESIGN.md 7.14): every trip of a year as a barcode, saved as a
/// picture and handed to the phone's share sheet by one button.
///
/// The picture is the poster the page shows, drawn again at 1920 x 1080. The app
/// uploads nothing: it writes the file and Android's own sheet takes over.
class YearPanel extends StatefulWidget {
  const YearPanel({
    super.key,
    required this.years,
    required this.build,
    required this.sweetSpot,
    required this.initialYear,
    required this.sharer,
  });

  /// The years that have trips, newest first.
  final List<int> years;

  /// The poster's data for a year.
  final YearOnTape Function(int year) build;

  /// The sweet spot as "55–70", or null.
  final String? sweetSpot;

  final int initialYear;
  final ImageSharer sharer;

  @override
  State<YearPanel> createState() => YearPanelState();
}

class YearPanelState extends State<YearPanel> {
  late int _year = widget.initialYear;
  ShareStatus _status = ShareStatus.idle;

  int get year => _year;
  ShareStatus get status => _status;

  /// The name of the saved picture: tapedash-2026.
  static String fileName(int year) => 'tapedash-$year';

  /// Draws the poster and hands it to the share sheet.
  Future<void> share() async {
    if (_status == ShareStatus.working) return;
    setState(() => _status = ShareStatus.working);
    final palette = TapePalette(livery: TapeTheme.of(context).livery);
    final Uint8List png = await YearPosterPainter.toPng(
      widget.build(_year),
      palette,
      sweetSpot: widget.sweetSpot,
    );
    final ok = await widget.sharer.sharePng(png, name: fileName(_year));
    if (!mounted) return;
    setState(() => _status = ok ? ShareStatus.shared : ShareStatus.failed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = TapePalette(livery: theme.livery);
    final poster = widget.build(_year);
    return InsightPanel(
      factsWidth: 0.26,
      chart: Center(
        child: poster.isEmpty
            ? const InsightEmpty(
                title: 'No trips this year yet',
                how:
                    'Every trip of the year is a bar of one barcode. Drive, and it fills in.',
              )
            : YearPoster(year: poster, sweetSpot: widget.sweetSpot),
      ),
      facts: [
        TapeButton(
          label: 'Share',
          icon: TapeIcon.share,
          primary: true,
          onPressed: poster.isEmpty || _status == ShareStatus.working
              ? null
              : share,
        ),
        const SizedBox(height: TapeSpace.s3),
        if (widget.years.length > 1) ...[
          TapeSegmented<int>(
            segments: [
              for (final y in widget.years.take(3)) TapeSegment(y, '$y'),
            ],
            value: _year,
            onChanged: (y) => setState(() {
              _year = y;
              _status = ShareStatus.idle;
            }),
          ),
          const SizedBox(height: TapeSpace.s3),
        ],
        InsightNote(switch (_status) {
          ShareStatus.working => 'Drawing the picture…',
          ShareStatus.shared => 'Handed to your share sheet.',
          ShareStatus.failed => 'Nothing on this phone could take the picture.',
          ShareStatus.idle =>
            'Saved as a picture and opened in your phone\'s share sheet. TapeDash uploads nothing.',
        }, color: _status == ShareStatus.failed ? palette.caution : null),
      ],
    );
  }
}
