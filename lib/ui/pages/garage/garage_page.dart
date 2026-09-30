import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../app/app_services.dart';
import '../../../app/app_settings.dart';
import '../../../app/drive_sound.dart';
import '../../../core/fuel_blend.dart';
import '../../../core/observable.dart';
import '../../../fuel/fuel_constants.dart';
import '../../../money/calibration.dart';
import '../../../obd/adapter_config.dart';
import '../../../sound/engine_profile.dart';
import '../../../sound/engine_sound.dart' show SoundStatus;
import '../../../trips/trip_library.dart';
import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/controls/slide_to_confirm.dart';
import '../../design/components/controls/tape_button.dart';
import '../../design/components/controls/tape_list_row.dart';
import '../../design/components/controls/tape_segmented.dart';
import '../../design/components/controls/tape_slider.dart';
import '../../design/components/controls/tape_toggle.dart';
import '../../design/components/tape_label.dart';
import '../../design/fidelity/fidelity_tier.dart';
import '../../design/icons/icons.dart';
import '../../design/motion/ignition_sequence.dart';
import '../../design/motion/observable_listenable.dart';
import '../../design/theme/mode_controller.dart' show ModeSetting;
import '../../design/theme/palette.dart' show DriverSide;
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/colors.dart' show HudColor;
import '../../design/tokens/livery.dart';
import '../../design/tokens/spacing.dart';
import '../../dev/demo_control.dart';

/// Garage (DESIGN.md 7.8): the settings, in groups under bracketed headers.
///
/// Car, the drive cluster and its look, the HUD, the fuel price, the coach, the
/// display, the demo, the data and what the app is. Each control changes its
/// setting at once and it is remembered (defaults over settings: nothing here has to
/// be touched). Parked only: it closes itself if the car starts to move.
///
/// Not here yet, and said so in `docs/STATUS.md`: the adapter (phase 6 puts it
/// here), currency and units, shift-light settings, automatic brightness, CSV
/// export, and the licence screen's QR code.
class GaragePage extends StatefulWidget {
  const GaragePage({
    super.key,
    required this.settings,
    required this.services,
    required this.library,
    required this.mode,
    required this.width,
    required this.height,
    required this.onClose,
    this.onSetPrice,
    this.adapters,
    this.onChangeAdapter,
    this.phoneTemperature,
    this.demo,
    this.onEndTrip,
    this.onAlignment,
    this.sound,
    this.version = 'dev',
  });

  /// The engine sound, for its group: null leaves the group out.
  final DriveSound? sound;

  final AppSettings settings;

  /// The car's own settings and money: the real ones (a demo drive has its own).
  final AppServices services;
  final TripLibrary library;
  final ValueListenable<DrivingMode> mode;
  final double width;
  final double height;
  final VoidCallback onClose;

  /// Opens the price form.
  final VoidCallback? onSetPrice;

  /// The adapter the user chose, and how it is used.
  final AdapterStore? adapters;

  /// Opens the connect flow, to choose or change the adapter.
  final VoidCallback? onChangeAdapter;

  /// The battery temperature, for the suggestion when the phone is hot.
  final Observable<double?>? phoneTemperature;

  /// The demo's controls, when there is one.
  final DemoControl? demo;

  /// Ends the trip that is going, now (demo).
  final VoidCallback? onEndTrip;

  /// Puts the HUD's alignment pattern up.
  final VoidCallback? onAlignment;

  final String version;

  @override
  State<GaragePage> createState() => GaragePageState();
}

/// A list to pick one of, in place of the Garage while it is open.
class _Choice {
  const _Choice(this.title, this.entries);

  final String title;
  final List<({String label, bool selected, VoidCallback pick})> entries;
}

class GaragePageState extends State<GaragePage> {
  _Choice? _choice;
  late final Listenable _changes;
  final ValueNotifier<int> _deleted = ValueNotifier(0);
  final ScrollController _scroll = ScrollController();
  double _savedOffset = 0;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _changes = Listenable.merge([
      s.livery,
      s.driverSide,
      s.ignition,
      s.reduceMotion,
      s.tierPin,
      s.cluster,
      s.coachPreset,
      s.speedLimitKmh,
      s.demoScenario,
      s.demoProfile,
      s.hud,
      s.soundEnabled,
      s.soundProfile,
      s.soundVolume,
      s.soundOnSpeaker,
      if (widget.sound != null) ...[
        widget.sound!.status,
        widget.sound!.testing,
      ],
      ObservableListenable(widget.services.setup),
      ObservableListenable(widget.services.money.price),
      ObservableListenable(widget.services.ledger.confidence),
      if (widget.phoneTemperature != null)
        ObservableListenable(widget.phoneTemperature!),
      if (widget.adapters != null) ...[
        ObservableListenable(widget.adapters!.adapter),
        ObservableListenable(widget.adapters!.useAdapter),
        ObservableListenable(widget.adapters!.compatibilityMode),
        ObservableListenable(widget.adapters!.recordSessions),
      ],
      _deleted,
    ]);
    widget.mode.addListener(_onMode);
  }

  @override
  void dispose() {
    widget.mode.removeListener(_onMode);
    _deleted.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onMode() {
    if (widget.mode.value != DrivingMode.parked) widget.onClose();
  }

  /// Whether a list to pick from is open.
  bool get isPicking => _choice != null;

  static const List<String> clusterNames = [
    'Apex',
    'Tape',
    'Minimal',
    'Telemetry',
    'Road',
  ];

  void _pick(_Choice choice) {
    _savedOffset = _scroll.hasClients ? _scroll.offset : 0;
    setState(() => _choice = choice);
  }

  // The page comes back where it was left.
  void _endPick() {
    setState(() => _choice = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(_savedOffset);
    });
  }

  _Choice _choose<T>(
    String title,
    List<(T, String)> options,
    T current,
    ValueChanged<T> onPick,
  ) => _Choice(title, [
    for (final (value, label) in options)
      (
        label: label,
        selected: value == current,
        pick: () {
          onPick(value);
          _endPick();
        },
      ),
  ]);

  @override
  Widget build(BuildContext context) {
    final margin = TapeSpace.margin(widget.height);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(margin, margin, margin, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TapeLabel(_choice?.title ?? 'Garage', size: 12),
                const Spacer(),
                TapeButton(
                  label: _choice == null ? 'Close' : 'Back',
                  icon: _choice == null ? TapeIcon.close : TapeIcon.back,
                  compact: true,
                  onPressed: _choice == null ? widget.onClose : _endPick,
                ),
              ],
            ),
            const SizedBox(height: TapeSpace.s1),
            Expanded(
              child: AnimatedBuilder(
                animation: _changes,
                builder: (context, _) =>
                    _choice != null ? _choiceList(_choice!) : _groups(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceList(_Choice choice) => ListView(
    key: ValueKey(choice.title),
    physics: const ClampingScrollPhysics(),
    children: [
      for (final e in choice.entries)
        TapeListRow(
          label: e.label,
          selected: e.selected,
          chevron: false,
          onTap: e.pick,
        ),
    ],
  );

  Widget _groups(BuildContext context) {
    final s = widget.settings;
    final app = widget.services;
    final setup = app.setup.value;
    final price = app.money.price.value;
    final confidence = app.ledger.confidence.value;
    final demo = widget.demo;
    final adapters = widget.adapters;

    return ListView(
      key: const ValueKey('groups'),
      controller: _scroll,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: TapeSpace.s8),
      children: [
        _Group('Car', [
          _Field(
            'Fuel',
            TapeSegmented<FuelType>(
              height: 40,
              value: setup.fuelType,
              onChanged: (t) =>
                  app.setVehicleSetup(setup.copyWith(fuelType: t)),
              segments: const [
                TapeSegment(FuelType.petrol, 'Petrol'),
                TapeSegment(FuelType.diesel, 'Diesel'),
              ],
            ),
          ),
          if (setup.fuelType == FuelType.petrol)
            _Field(
              'Ethanol in the petrol',
              TapeSegmented<PetrolBlend>(
                height: 40,
                value: setup.blend,
                onChanged: (b) => app.setVehicleSetup(setup.copyWith(blend: b)),
                segments: [
                  for (final b in PetrolBlend.values) TapeSegment(b, b.label),
                ],
              ),
            ),
          TapeSlider(
            label: 'Engine size',
            value: setup.displacementLitres,
            min: 0.6,
            max: 6,
            format: (v) => '${v.toStringAsFixed(1)} L',
            onChanged: (v) => app.setVehicleSetup(
              setup.copyWith(displacementLitres: (v * 10).round() / 10),
            ),
          ),
          TapeSlider(
            label: 'Tank',
            value: setup.tankLitres,
            min: 20,
            max: 120,
            format: (v) => '${v.round()} L',
            onChanged: (v) => app.setVehicleSetup(
              setup.copyWith(tankLitres: v.roundToDouble()),
            ),
          ),
          _Info('Fuel figures', switch (confidence) {
            CalibrationConfidence.uncalibrated =>
              'Estimates. Two full tanks in Pit Stop check them.',
            CalibrationConfidence.calibrating =>
              'Estimates, checked once. One more full tank helps.',
            CalibrationConfidence.calibrated => 'Estimates, checked twice.',
          }),
        ]),
        if (adapters != null) _adapterGroup(adapters),
        _Group('Fuel price', [
          TapeListRow(
            label: 'Price a litre',
            value: price == null ? 'Not set' : '₹${price.toStringAsFixed(2)}',
            onTap: widget.onSetPrice,
          ),
        ]),
        _Group('Cluster', [
          TapeListRow(
            label: 'Layout',
            value: clusterNames[s.cluster.value],
            onTap: () => _pick(
              _choose<int>(
                'Layout',
                [
                  for (var i = 0; i < clusterNames.length; i++)
                    (i, clusterNames[i]),
                ],
                s.cluster.value,
                (i) => s.cluster.value = i,
              ),
            ),
          ),
          TapeListRow(
            label: 'Livery',
            value: Liveries.byId(s.livery.value).name,
            onTap: () => _pick(
              _choose<LiveryId>(
                'Livery',
                [
                  for (final l in Liveries.all)
                    (l.id, '${l.name}  ·  ${l.character}'),
                ],
                s.livery.value,
                (id) => s.livery.value = id,
              ),
            ),
          ),
          _Field(
            'Driver side',
            TapeSegmented<DriverSide>(
              height: 40,
              value: s.driverSide.value,
              onChanged: (v) => s.driverSide.value = v,
              segments: const [
                TapeSegment(DriverSide.left, 'Left'),
                TapeSegment(DriverSide.right, 'Right'),
              ],
            ),
          ),
        ]),
        _Group('HUD', [
          TapeListRow(
            label: 'Colour',
            value: s.hud.color.label,
            onTap: () => _pick(
              _choose<HudColor>(
                'HUD colour',
                [for (final c in HudColor.values) (c, c.label)],
                s.hud.color,
                (c) => s.hud.color = c,
              ),
            ),
          ),
          _Toggle(
            'Flip left to right (a windshield mirrors)',
            s.hud.flipHorizontal,
            (v) => s.hud.flipHorizontal = v,
          ),
          _Toggle(
            'Flip top to bottom',
            s.hud.flipVertical,
            (v) => s.hud.flipVertical = v,
          ),
          TapeSlider(
            label: 'Height on the glass',
            value: s.hud.verticalPosition,
            min: -1,
            max: 1,
            format: (v) => v.abs() < 0.05
                ? 'Middle'
                : '${(v.abs() * 100).round()}% ${v > 0 ? 'up' : 'down'}',
            onChanged: (v) => s.hud.verticalPosition = v,
          ),
          TapeSlider(
            label: 'Size',
            value: s.hud.scale,
            min: 0.6,
            max: 1.4,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) => s.hud.scale = v,
          ),
          TapeListRow(
            label: 'Alignment pattern',
            value: 'For setting the HUD up',
            onTap: widget.onAlignment == null
                ? null
                : () {
                    widget.onAlignment!();
                    widget.onClose();
                  },
          ),
        ]),
        _Group('Coach', [
          _Field(
            'Hard acceleration and braking',
            TapeSegmented<CoachPreset>(
              height: 40,
              value: s.coachPreset.value,
              onChanged: (v) => s.coachPreset.value = v,
              segments: [
                for (final p in CoachPreset.values) TapeSegment(p, p.label),
              ],
            ),
          ),
          TapeSlider(
            label: 'Speed threshold',
            value: s.speedLimitKmh.value,
            min: 60,
            max: 160,
            format: (v) => '${v.round()} km/h',
            onChanged: (v) => s.speedLimitKmh.value = (v / 5).round() * 5.0,
          ),
        ]),
        if (widget.sound != null) _soundGroup(s, widget.sound!),
        _Group('Display', [
          _Field(
            'Brightness mode',
            TapeSegmented<ModeSetting>(
              height: 40,
              value: s.modeSetting.value,
              onChanged: (v) => s.modeSetting.value = v,
              segments: [
                for (final m in ModeSetting.values) TapeSegment(m, m.label),
              ],
            ),
          ),
          if ((widget.phoneTemperature?.value ?? 0) > 45)
            _Info(
              'The phone is hot (${widget.phoneTemperature!.value!.round()}°C)',
              'Unplug the charger and move it out of the sun. Above 50°C the screen '
                  'dims and the display eases off by itself.',
            ),
          _Toggle(
            'Reduce motion',
            s.reduceMotion.value,
            (v) => s.reduceMotion.value = v,
          ),
          _Field(
            'Fidelity',
            TapeSegmented<FidelityTier?>(
              height: 40,
              value: s.tierPin.value,
              onChanged: (v) => s.tierPin.value = v,
              segments: [
                const TapeSegment<FidelityTier?>(null, 'Auto'),
                for (final t in FidelityTier.values)
                  TapeSegment<FidelityTier?>(t, t.label),
              ],
            ),
          ),
          _Field(
            'Ignition sequence',
            TapeSegmented<IgnitionMode>(
              height: 40,
              value: s.ignition.value,
              onChanged: (v) => s.ignition.value = v,
              segments: const [
                TapeSegment(IgnitionMode.off, 'Off'),
                TapeSegment(IgnitionMode.subtle, 'Subtle'),
                TapeSegment(IgnitionMode.full, 'Full'),
              ],
            ),
          ),
        ]),
        if (demo != null)
          _Group('Demo mode', [
            TapeListRow(
              label: 'Drive',
              value: demo.scenario.value,
              onTap: () => _pick(
                _choose<String>(
                  'Demo drive',
                  [for (final n in demo.scenarios) (n, n)],
                  demo.scenario.value,
                  (n) {
                    s.demoScenario.value = n;
                    demo.select(scenario: n);
                  },
                ),
              ),
            ),
            TapeListRow(
              label: 'Car',
              value: demo.profile.value.isEmpty
                  ? 'Default'
                  : demo.profile.value,
              onTap: () => _pick(
                _choose<String>(
                  'Demo car',
                  [('', 'Default'), for (final n in demo.profiles) (n, n)],
                  demo.profile.value,
                  (n) {
                    s.demoProfile.value = n;
                    demo.select(profile: n);
                  },
                ),
              ),
            ),
            if (widget.onEndTrip != null)
              TapeListRow(
                label: 'End this trip now',
                chevron: false,
                onTap: () {
                  widget.onEndTrip!();
                  widget.onClose();
                },
              ),
          ]),
        _Group('Data', [
          const _Info(
            'Everything stays on this phone',
            'Trips, fill-ups and settings are stored here and nowhere else.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: TapeSpace.s2),
            child: SlideToConfirm(
              label: 'Slide to delete all trips and fill-ups',
              onConfirmed: _deleteAll,
            ),
          ),
        ]),
        _Group('About', [
          _Info(
            'TapeDash ${widget.version}',
            'Free and open source (Apache-2.0). It works entirely offline: no '
                'account, no analytics, no ads and no network calls. Fuel and '
                'money figures are estimates.',
          ),
        ]),
      ],
    );
  }

  Widget _adapterGroup(AdapterStore adapters) {
    final chosen = adapters.adapter.value;
    return _Group('Adapter', [
      TapeListRow(
        label: 'Adapter',
        value: chosen == null
            ? 'None: demo mode'
            : '${chosen.displayName}  ·  ${chosen.kind.label}',
        onTap: widget.onChangeAdapter,
      ),
      if (chosen != null) ...[
        _Toggle(
          'Drive from this adapter',
          adapters.useAdapter.value,
          (v) => adapters.setUseAdapter(v),
        ),
        _Toggle(
          'Compatibility mode (slower, for fussy adapters)',
          adapters.compatibilityMode.value,
          (v) => adapters.setCompatibilityMode(v),
        ),
        _Toggle(
          'Record what the adapter says',
          adapters.recordSessions.value,
          (v) => adapters.setRecordSessions(v),
        ),
        if (adapters.recordSessions.value)
          const _Info(
            'Saved on this phone',
            'One file for each drive, in Android/data/io.github.ictashik.tapedash/'
                'files/recordings. Nothing leaves the phone by itself.',
          ),
        TapeListRow(
          label: 'Forget this adapter',
          chevron: false,
          onTap: () => adapters.forget(),
        ),
      ],
    ]);
  }

  /// The engine sound (lib/sound): off until turned on. It plays only on car audio
  /// unless the speaker is allowed, and the test plays on whatever there is.
  Widget _soundGroup(AppSettings s, DriveSound sound) {
    final profile = EngineProfile.byId(s.soundProfile.value);
    final testing = sound.testing.value;
    return _Group('Engine sound', [
      _Toggle(
        'Engine sound',
        s.soundEnabled.value,
        (v) => s.soundEnabled.value = v,
      ),
      TapeListRow(
        label: 'Engine',
        value: profile.name,
        onTap: () => _pick(
          _choose<String>(
            'Engine',
            [
              for (final p in EngineProfile.all)
                (p.id, '${p.name}  ·  ${p.description}'),
            ],
            profile.id,
            (id) => s.soundProfile.value = id,
          ),
        ),
      ),
      TapeSlider(
        label: 'Volume',
        value: s.soundVolume.value,
        min: 0.05,
        max: 1,
        format: (v) => '${(v * 100).round()}%',
        onChanged: (v) => s.soundVolume.value = (v * 20).round() / 20,
      ),
      _Toggle(
        'Also on the phone speaker',
        s.soundOnSpeaker.value,
        (v) => s.soundOnSpeaker.value = v,
      ),
      TapeListRow(
        label: testing ? 'Stop the test' : 'Test the sound',
        value: testing ? 'Playing' : 'Ten seconds, on whatever output there is',
        chevron: false,
        onTap: () => sound.test(),
      ),
      _Info(_soundStatus(sound.status.value, s.soundEnabled.value), _soundNote),
    ]);
  }

  static const String _soundNote =
      'It plays on car audio (Bluetooth, a wire, USB) and stops when the app leaves '
      'the screen. Turned on, it follows the revs: a replay in Review has it too.';

  static String _soundStatus(SoundStatus status, bool enabled) {
    if (!enabled) return 'Off';
    return switch (status) {
      SoundStatus.off => 'On: starts when the app is on screen',
      SoundStatus.starting => 'Starting',
      SoundStatus.playing => 'Playing',
      SoundStatus.noOutput =>
        'No car audio to play on: connect the phone to the car, or allow the speaker',
      SoundStatus.lost =>
        'Stopped: the audio output went away. Turn it off and on to start again',
      SoundStatus.failed => 'The phone would not start its audio output',
    };
  }

  Future<void> _deleteAll() async {
    await widget.services.deleteAllData();
    await widget.library.refresh();
    if (mounted) _deleted.value++;
  }
}

/// A group of rows under a bracketed header (DESIGN.md 7.8).
class _Group extends StatelessWidget {
  const _Group(this.title, this.rows);

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return Padding(
      padding: const EdgeInsets.only(top: TapeSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TapeLabel('[', size: 12, color: palette.accentCore),
              const SizedBox(width: TapeSpace.s1),
              TapeLabel(title, size: 12, color: palette.inkMid),
              const SizedBox(width: TapeSpace.s1),
              TapeLabel(']', size: 12, color: palette.accentCore),
            ],
          ),
          const SizedBox(height: TapeSpace.s1),
          ...rows,
        ],
      ),
    );
  }
}

/// A label over a control.
class _Field extends StatelessWidget {
  const _Field(this.label, this.control);

  final String label;
  final Widget control;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: TapeSpace.s1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TapeLabel(label, size: 11),
        const SizedBox(height: TapeSpace.s1),
        control,
      ],
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.value, this.onChanged);

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onChanged(!value),
    child: SizedBox(
      height: TapeSpace.touchTarget,
      child: Row(
        children: [
          Expanded(child: TapeText(label, maxLines: 1)),
          TapeToggle(value: value, onChanged: onChanged, semanticLabel: label),
        ],
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TapeSpace.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TapeText(title, style: TapeTextStyle.small, color: palette.inkBright),
          TapeText(body, style: TapeTextStyle.caption, color: palette.inkMid),
        ],
      ),
    );
  }
}
