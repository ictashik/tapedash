/// How an engine sounds (see `EngineSynth`): a parameter set, not a recording.
/// Every profile is made in code, so there is no audio asset to license, nothing
/// added to the APK, and nothing that claims to be a particular car: the names are
/// the engine layouts, not the makes.
///
/// A profile says how the engine fires (how many cylinders, and how evenly), how
/// the exhaust shapes each pulse (the pulse's length, the pipe's length and how
/// ringing it is, the body's resonances, how muffled it is), and what rides on top
/// (the intake, the valve train, a turbo's whistle and blow-off, the pops of an
/// overrun). An electric profile has none of that and whines instead.
enum EngineKind { combustion, electric }

/// One resonance of the body and exhaust: a band-pass at [hz] of quality [q], mixed
/// in at [gain] alongside the pipe's own sound.
class Formant {
  const Formant(this.hz, this.q, this.gain);

  final double hz;
  final double q;
  final double gain;
}

class EngineProfile {
  const EngineProfile({
    required this.id,
    required this.name,
    required this.description,
    this.kind = EngineKind.combustion,
    this.cylinders = 4,
    this.cylinderGains = const [],
    this.pulseSeconds = 0.0009,
    this.pipeMetres = 1.3,
    this.pipeFeedback = 0.5,
    this.pipeDamping = 0.35,
    this.formants = const [],
    this.brightnessHz = 2600,
    this.lope = 0.12,
    this.intake = 0.12,
    this.valvetrain = 0.05,
    this.turbo = 0,
    this.crackle = 0,
    this.whineHz = 0,
    this.whinePerRpm = 0,
    this.whineGain = 0,
    this.idleRpm = 800,
    this.redlineRpm = 6500,
  });

  /// The profile's key, for settings: stable, lower-case.
  final String id;

  /// What the Garage calls it.
  final String name;

  /// One line for the Garage, about how it sounds.
  final String description;

  final EngineKind kind;

  /// How many cylinders: a four-stroke fires [cylinders] / 2 of them each turn of
  /// the crank, and the firing's pitch is the revs per second times that.
  final int cylinders;

  /// How hard each cylinder fires relative to the others, in firing order: an
  /// uneven list is a lumpy, burbling engine. Empty is all the same.
  final List<double> cylinderGains;

  /// How long the exhaust pulse of one firing is (a corner of two poles at its
  /// reciprocal): short is crisp, long is dull and deep.
  final double pulseSeconds;

  /// The exhaust pipe: its length in metres sets the pitch it rings at (round trip
  /// at the speed of sound in hot gas), [pipeFeedback] how long it rings, and
  /// [pipeDamping] how much of the top is lost on every trip down it.
  final double pipeMetres;
  final double pipeFeedback;
  final double pipeDamping;

  /// The body's resonances.
  final List<Formant> formants;

  /// The top of the sound, with the throttle shut: the muffler. The throttle opens
  /// it up.
  final double brightnessHz;

  /// How uneven the idle is, 0 to 1: each firing's strength and timing are a little
  /// off, more so at low revs, so it burbles instead of buzzing.
  final double lope;

  /// How loud the intake's rush is with the throttle open, and the valve train's
  /// tick at each firing: 0 to 1.
  final double intake;
  final double valvetrain;

  /// A turbo's whistle with load (0 to 1), and the hiss when the throttle closes.
  final double turbo;

  /// The pops of an overrun, 0 to 1.
  final double crackle;

  /// Electric: a whine from [whineHz] rising by [whinePerRpm] for each rpm, three
  /// harmonics of it, at [whineGain].
  final double whineHz;
  final double whinePerRpm;
  final double whineGain;

  /// The revs it idles at and where it stops, for the gain that rises with them.
  final double idleRpm;
  final double redlineRpm;

  bool get isElectric => kind == EngineKind.electric;

  /// The engines on offer, in the order the Garage lists them.
  static const List<EngineProfile> all = [
    inline4,
    inline3,
    v6,
    v8,
    flat6,
    turbo4,
    electric,
  ];

  /// The profile with [id], or the first if there is none.
  static EngineProfile byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);

  static const EngineProfile inline4 = EngineProfile(
    id: 'inline4',
    name: 'Inline-4',
    description: 'A smooth four: a steady hum that climbs',
    cylinders: 4,
    pulseSeconds: 0.0009,
    pipeMetres: 1.2,
    pipeFeedback: 0.48,
    formants: [
      Formant(120, 2.5, 0.9),
      Formant(330, 3, 0.55),
      Formant(900, 3, 0.3),
    ],
    brightnessHz: 2600,
    lope: 0.10,
    intake: 0.12,
    valvetrain: 0.05,
  );

  static const EngineProfile inline3 = EngineProfile(
    id: 'inline3',
    name: 'Three-cylinder',
    description: 'A rough little triple: lumpy, eager',
    cylinders: 3,
    cylinderGains: [1.0, 0.86, 0.94],
    pulseSeconds: 0.0011,
    pipeMetres: 1.1,
    pipeFeedback: 0.5,
    formants: [
      Formant(105, 2.5, 1.0),
      Formant(280, 3, 0.6),
      Formant(760, 3, 0.3),
    ],
    brightnessHz: 2300,
    lope: 0.30,
    intake: 0.10,
    valvetrain: 0.06,
    idleRpm: 850,
  );

  static const EngineProfile v6 = EngineProfile(
    id: 'v6',
    name: 'V6',
    description: 'A deep, smooth six',
    cylinders: 6,
    pulseSeconds: 0.0012,
    pipeMetres: 1.7,
    pipeFeedback: 0.52,
    pipeDamping: 0.42,
    formants: [
      Formant(90, 2.2, 1.0),
      Formant(240, 3, 0.6),
      Formant(650, 3, 0.3),
    ],
    brightnessHz: 2200,
    lope: 0.08,
    intake: 0.10,
    valvetrain: 0.04,
    idleRpm: 700,
    redlineRpm: 6800,
  );

  static const EngineProfile v8 = EngineProfile(
    id: 'v8',
    name: 'V8',
    description: 'A big V8: a burble at idle, a growl under load',
    cylinders: 8,
    cylinderGains: [1.0, 0.72, 0.92, 0.64, 0.98, 0.7, 0.88, 0.66],
    pulseSeconds: 0.0014,
    pipeMetres: 2.0,
    pipeFeedback: 0.56,
    pipeDamping: 0.45,
    formants: [
      Formant(72, 2.0, 1.1),
      Formant(190, 2.6, 0.7),
      Formant(520, 3, 0.35),
    ],
    brightnessHz: 1900,
    lope: 0.22,
    intake: 0.14,
    valvetrain: 0.04,
    crackle: 0.35,
    idleRpm: 650,
    redlineRpm: 6200,
  );

  static const EngineProfile flat6 = EngineProfile(
    id: 'flat6',
    name: 'Flat-six',
    description: 'A rasping boxer: hard-edged, rising to a howl',
    cylinders: 6,
    pulseSeconds: 0.0006,
    pipeMetres: 1.4,
    pipeFeedback: 0.5,
    pipeDamping: 0.25,
    formants: [
      Formant(130, 2.5, 0.8),
      Formant(480, 3.5, 0.6),
      Formant(1250, 4, 0.45),
    ],
    brightnessHz: 4200,
    lope: 0.06,
    intake: 0.12,
    valvetrain: 0.08,
    idleRpm: 900,
    redlineRpm: 7500,
  );

  static const EngineProfile turbo4 = EngineProfile(
    id: 'turbo4',
    name: 'Turbo four',
    description:
        'A four with a turbo: a whistle under load, a hiss on the lift',
    cylinders: 4,
    pulseSeconds: 0.0008,
    pipeMetres: 1.3,
    pipeFeedback: 0.45,
    formants: [
      Formant(135, 2.5, 0.8),
      Formant(400, 3, 0.55),
      Formant(1000, 3, 0.3),
    ],
    brightnessHz: 2800,
    lope: 0.10,
    intake: 0.16,
    valvetrain: 0.05,
    turbo: 0.85,
    crackle: 0.2,
    idleRpm: 820,
    redlineRpm: 6800,
  );

  static const EngineProfile electric = EngineProfile(
    id: 'electric',
    name: 'Electric',
    description: 'A motor and its inverter: a whine that follows the revs',
    kind: EngineKind.electric,
    cylinders: 4,
    whineHz: 380,
    whinePerRpm: 0.55,
    whineGain: 1.0,
    intake: 0.05,
    lope: 0,
    idleRpm: 0,
    redlineRpm: 6500,
  );
}
