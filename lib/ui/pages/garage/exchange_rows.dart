import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../app/exchange_coordinator.dart';
import '../../design/components/controls/tape_button.dart';
import '../../design/components/tape_label.dart';
import '../../design/icons/icons.dart';
import '../../design/motion/observable_listenable.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';

/// Garage's rows for moving the app's data out and in (docs/EXCHANGE.md 6): EXPORT,
/// IMPORT (from a file the phone's own picker gives, and from what waits in the
/// inbox folder), what the last one did in a sentence, and, when a file brought a
/// setup, what it would change and a button to apply it.
///
/// The phone has a picker and a share sheet and so shows both; a watch has neither
/// and shows the folder. Nothing here sends anything anywhere: a share sheet is
/// Android's, and what is picked in it is the person's.
class ExchangeRows extends StatefulWidget {
  const ExchangeRows({super.key, required this.exchange});

  final ExchangeCoordinator exchange;

  @override
  State<ExchangeRows> createState() => _ExchangeRowsState();
}

class _ExchangeRowsState extends State<ExchangeRows> {
  bool _canPick = false;
  bool _canShare = false;
  late final ObservableListenable<ExchangeStatus> _status =
      ObservableListenable(widget.exchange.status);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final c = await widget.exchange.capabilities();
    await widget.exchange.refresh();
    if (!mounted) return;
    setState(() {
      _canPick = c.canPick;
      _canShare = c.canShare;
    });
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return ListenableBuilder(
      listenable: _status,
      builder: (context, _) {
        final s = widget.exchange.status.value;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: TapeSpace.s2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: TapeSpace.s2,
                runSpacing: TapeSpace.s2,
                children: [
                  TapeButton(
                    label: 'Export',
                    icon: TapeIcon.share,
                    compact: true,
                    onPressed: s.busy
                        ? null
                        : () => unawaited(
                            widget.exchange.exportAll(share: _canShare),
                          ),
                  ),
                  if (_canPick)
                    TapeButton(
                      label: 'Import a file',
                      icon: TapeIcon.back,
                      compact: true,
                      onPressed: s.busy
                          ? null
                          : () => unawaited(widget.exchange.importPicked()),
                    ),
                  if (s.inboxFiles > 0)
                    TapeButton(
                      label: s.inboxFiles == 1
                          ? 'Import 1 waiting'
                          : 'Import ${s.inboxFiles} waiting',
                      icon: TapeIcon.back,
                      compact: true,
                      onPressed: s.busy
                          ? null
                          : () => unawaited(widget.exchange.importInbox()),
                    ),
                ],
              ),
              if (s.sentence != null)
                Padding(
                  padding: const EdgeInsets.only(top: TapeSpace.s2),
                  child: TapeText(
                    s.sentence!,
                    style: TapeTextStyle.small,
                    color: s.ok ? palette.inkBright : palette.caution,
                  ),
                ),
              if (s.offered.isNotEmpty) ...[
                const SizedBox(height: TapeSpace.s2),
                TapeText(
                  'The file has a setup that would change:',
                  style: TapeTextStyle.caption,
                  color: palette.inkMid,
                ),
                for (final line in s.offered)
                  TapeText(
                    line,
                    style: TapeTextStyle.caption,
                    color: palette.inkBright,
                  ),
                const SizedBox(height: TapeSpace.s2),
                TapeButton(
                  label: 'Apply the setup',
                  compact: true,
                  onPressed: () => unawaited(widget.exchange.applyOffered()),
                ),
              ],
              const SizedBox(height: TapeSpace.s2),
              TapeText(
                'Files go to and come from this app\'s own folders (outbox and '
                'inbox), which a computer reaches with adb. See docs/EXCHANGE.md.',
                style: TapeTextStyle.caption,
                color: palette.inkDim,
              ),
            ],
          ),
        );
      },
    );
  }
}
