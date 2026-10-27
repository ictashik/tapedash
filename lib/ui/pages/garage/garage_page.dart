import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../app/app_services.dart';
import '../../../app/app_settings.dart';
import '../../../app/drive_sound.dart';
import '../../../app/exchange_coordinator.dart';
import '../../../app/nav_service.dart';
import '../../../core/fuel_blend.dart';
import '../../../core/observable.dart';
import '../../../fuel/fuel_constants.dart';
import '../../../money/calibration.dart';
import '../../../obd/adapter_config.dart';
import '../../../obd/link_diary.dart';
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
import 'exchange_rows.dart';

/// Garage (DESIGN.md 7.8): the settings, in groups under bracketed headers.
///
/// Car, where the speed comes from, the drive cluster and its look, the HUD, the
/// fuel price, the coach, the display, the data and what the app is. Each control changes its
/// setting at once and it is remembered (defaults over settings: nothing here has to
/// be touched). Parked only: it closes itself if the car starts to move.
///
/// Not here yet, and said so in `docs/STATUS.md`: currency and units, shift-light settings, automatic brightness, CSV
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
    this.onSurvey,
    this.diary,
    this.phoneTemperature,
    this.gpsOnly = false,
    this.onAlignment,
    this.sound,
    this.nav,
    this.version = 'dev',
    this.exchange,
  });

  /// Moves the app's data out and in (docs/EXCHANGE.md): the Data group's rows. Null
  /// leaves them out.
  final ExchangeCoordinator? exchange;

  /// The engine sound, for its group: null leaves the group out.
  final DriveSound? sound;

  /// The navigation HUD's feed (docs/NAV.md), for its group: null leaves the group
  /// out.
  final NavService? nav;

  final AppSettings settings;

  /// The car's own settings and money.
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

  /// Starts a survey drive (docs/SURVEY.md). Null leaves the row out: there is
  /// no real adapter to survey.
  final VoidCallback? onSurvey;

  /// What the app has done to reach the adapter, for the connection log row. Null
  /// leaves the row out.
  final LinkDiary? diary;

  /// The battery temperature, for the suggestion when the phone is hot.
  final Observable<double?>? phoneTemperature;

  /// Whether the drive is on the GPS alone: the groups about the car (its fuel,
  /// the price, the coach, the cluster's layout, the trips) have nothing to
  /// change and are left out.
  final bool gpsOnly;

  /// Puts the HUD's alignment pattern up.
  final VoidCallback? onAlignment;

  final String version;

  @override
  State<GaragePage> createState() => GaragePageState();
}

/// A list to pick one of, in place of the Garage while it is open.
class _Choice {
  const _Choice(this.title, this.entries, {this.lines});

  final String title;
  final List<({String label, bool selected, VoidCallback pick})> entries;

  /// Plain lines to read instead of entries to pick (the connection log).
  final List<String>? lines;
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
      s.hud,
      s.soundEnabled,
      s.soundProfile,
      s.soundVolume,
      s.soundOnSpeaker,
      s.navEnabled,
      if (widget.nav != null) ...[widget.nav!.status, widget.nav!.access],
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
        ObservableListenable(widget.adapters!.source),
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
      if (choice.lines != null)
        for (final line in choice.lines!)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: TapeText(
              line,
              style: TapeTextStyle.caption,
              color: TapeTheme.of(context).palette.inkMid,
              maxLines: 2,
            ),
          ),
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
    final adapters = widget.adapters;
    final gpsOnly = widget.gpsOnly;

    return ListView(
      key: const ValueKey('groups'),
      controller: _scroll,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: TapeSpace.s8),
      children: [
        if (adapters != null) _adapterGroup(adapters),
        if (!gpsOnly)
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
                  onChanged: (b) =>
                      app.setVehicleSetup(setup.copyWith(blend: b)),
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
        if (!gpsOnly)
          _Group('Fuel price', [
            TapeListRow(
              label: 'Price a litre',
              value: price == null ? 'Not set' : '₹${price.toStringAsFixed(2)}',
              onTap: widget.onSetPrice,
            ),
          ]),
        _Group('Cluster', [
          if (!gpsOnly)
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
        if (widget.nav != null) _navGroup(s, widget.nav!),
        if (!gpsOnly)
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
        if (!gpsOnly || widget.exchange != null)
          _Group('Data', [
            const _Info(
              'Everything stays on this phone',
              'Trips, fill-ups and settings are stored here and nowhere else.',
            ),
            if (widget.exchange != null)
              ExchangeRows(exchange: widget.exchange!),
            if (!gpsOnly)
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

  /// Where the speed comes from, and the adapter it may come from. The car's
  /// adapter and the phone's GPS are chosen between here; neither is ever
  /// swapped for the other by itself.
  Widget _adapterGroup(AdapterStore adapters) {
    final chosen = adapters.adapter.value;
    final source = adapters.source.value;
    return _Group('Speed from', [
      _Field(
        'Source',
        TapeSegmented<DriveSource>(
          height: 40,
          value: source ?? DriveSource.obd,
          onChanged: (v) {
            // The car needs an adapter; with none chosen the way to it is the
            // connect flow, and the source changes when it finishes.
            if (v == DriveSource.obd && chosen == null) {
              widget.onChangeAdapter?.call();
            } else {
              adapters.setSource(v);
            }
          },
          segments: const [
            TapeSegment(DriveSource.obd, 'Car adapter'),
            TapeSegment(DriveSource.gps, 'GPS only'),
          ],
        ),
      ),
      if (source == DriveSource.gps)
        const _Info(
          'GPS only',
          'Speed, distance and time from the phone\'s GPS. Nothing is read from '
              'the car, so there is no RPM, fuel or money.',
        ),
      TapeListRow(
        label: 'Adapter',
        value: chosen == null
            ? 'None'
            : '${chosen.displayName}  ·  ${chosen.kind.label}',
        onTap: widget.onChangeAdapter,
      ),
      if (chosen != null) ...[
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
        if (widget.onSurvey != null && source == DriveSource.obd)
          TapeListRow(
            label: 'Survey drive',
            value: 'Find out what your car reports',
            onTap: widget.onSurvey,
          ),
        if (widget.diary != null)
          TapeListRow(
            label: 'Connection log',
            value: widget.diary!.lines.value.isEmpty
                ? 'Nothing yet'
                : '${widget.diary!.lines.value.length} lines, newest first',
            onTap: () => _pick(
              _Choice(
                'Connection log',
                const [],
                lines: widget.diary!.lines.value.reversed.toList(),
              ),
            ),
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

  /// The navigation HUD (docs/NAV.md): off until turned on. It reads the turn that
  /// Google Maps shows in its notification, and says what stands in the way.
  Widget _navGroup(AppSettings s, NavService nav) {
    final status = nav.status.value;
    final (title, body) = _navStatus(status);
    return _Group('Navigation', [
      _Toggle(
        'Show Google Maps turns on the HUD',
        s.navEnabled.value,
        (v) => s.navEnabled.value = v,
      ),
      _Info(title, body),
      if (status == NavLinkStatus.needsAccess)
        TapeListRow(
          label: 'Open notification access',
          value: 'Android\'s own screen',
          chevron: false,
          onTap: () => nav.openAccessSettings(),
        ),
      const _Info('What this does', _navNote),
      const _Info('If a small map floats over the HUD', _navFloating),
      const _Info('If a card drops over the HUD at a turn', _navCard),
      if (status != NavLinkStatus.off && status != NavLinkStatus.noMaps)
        TapeListRow(
          label: 'Open Google Maps\' notification settings',
          value: 'Android\'s own screen',
          chevron: false,
          onTap: () => nav.openMapsNotificationSettings(),
        ),
    ]);
  }

  static const String _navNote =
      'Google Maps does the routing, on its own internet connection. TapeDash stays '
      'offline: it reads the turn from Google Maps\' notification, sends it nothing '
      'and keeps nothing. Android\'s notification access lets an app see every '
      'notification; TapeDash looks at Google Maps\' only. You can take the access '
      'away in Android\'s settings at any time.';

  // Google Maps shrinks to a floating window by itself when you leave it during a
  // route; a bright map on the glass is the one thing the HUD cannot have.
  static const String _navFloating =
      'Google Maps shows a small floating map when you switch away from it during a '
      'route. Turn that off in Android\'s settings (Apps, Special app access, '
      'Picture-in-picture), so that the HUD stays black. Then read the next note: '
      'with the floating map off, Google Maps shows its turns as a card instead.';

  // Google Maps moves its notification to a high-priority channel as a turn comes
  // up, and Android 16 then pops it over the screen as a card for a few seconds,
  // over the arrow and the distance. Found with real Maps on an emulator.
  static const String _navCard =
      'With the floating map off, Google Maps pops its notification over the screen '
      'as a card when a turn is near (on the test phone, about every turn). Open '
      'Google Maps\' notification settings below, open '
      'its list of categories, choose "Navigation urgent updates" (the names may '
      'differ in your language) and turn off "Pop on screen". Google Maps keeps '
      'guiding you.';

  static (String, String) _navStatus(NavLinkStatus status) => switch (status) {
    NavLinkStatus.off => ('Off', 'TapeDash is not reading any notification.'),
    NavLinkStatus.noMaps => (
      'Google Maps is not on this phone',
      'The HUD shows its turns while it is navigating on this phone.',
    ),
    NavLinkStatus.needsAccess => (
      'Needs notification access',
      'Open Android\'s screen below, turn TapeDash on, and come back.',
    ),
    NavLinkStatus.waiting => (
      'On: waiting for Google Maps',
      'Start a route in Google Maps and the HUD shows its next turn.',
    ),
    NavLinkStatus.guiding => (
      'On: following Google Maps',
      'The HUD shows its next turn.',
    ),
    NavLinkStatus.stale => (
      'Google Maps has gone quiet',
      'The turn on the HUD is not live. Open Google Maps to see where you are.',
    ),
  };

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
