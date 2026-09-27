import 'package:flutter/widgets.dart';

import 'motion_clock.dart';

/// Gives the widgets below it the one [MotionClock] (DESIGN.md 5.9).
///
/// [MotionScope] makes the app's vsync clock and disposes it. [MotionScope.value]
/// provides a clock someone else owns, which is how tests and the Design Lab's
/// captures give the components a clock they step by hand.
class MotionScope extends StatefulWidget {
  const MotionScope({super.key, required this.child}) : clock = null;

  const MotionScope.value({
    super.key,
    required MotionClock this.clock,
    required this.child,
  });

  final MotionClock? clock;
  final Widget child;

  /// The clock in effect.
  static MotionClock of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_MotionInherited>();
    assert(scope != null, 'No MotionScope above this widget');
    return scope!.clock;
  }

  static MotionClock? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MotionInherited>()?.clock;

  @override
  State<MotionScope> createState() => _MotionScopeState();
}

class _MotionScopeState extends State<MotionScope> {
  MotionClock? _owned;

  MotionClock get _clock => widget.clock ?? (_owned ??= VsyncMotionClock());

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _MotionInherited(clock: _clock, child: widget.child);
}

class _MotionInherited extends InheritedWidget {
  const _MotionInherited({required this.clock, required super.child});

  final MotionClock clock;

  @override
  bool updateShouldNotify(_MotionInherited oldWidget) =>
      clock != oldWidget.clock;
}
