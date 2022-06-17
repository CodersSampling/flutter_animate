import 'dart:math';

import 'package:flutter/widgets.dart';

import '../flutter_animate.dart';

/// Effect that shakes the target, using translation, rotation, or both.
/// The `count` parameter indicates how many times to repeat the shake within
/// the duration. Defaults to a 5 degree (`pi / 36`) shake, repeated 3 times —
/// equivalent to:
///
/// ```
/// Text("Hello").animate()
///   .shake(count: 3, rotation: pi / 36)
/// ```
///
/// There are also shortcut extensions for applying horizontal / vertical shake.
/// For example, this would shake 10 pixels horizontally (default is 6):
///
/// ```
/// Text("Hello").animate().shakeX(amount: 10)
/// ```
@immutable
class ShakeEffect extends Effect<double> {
  const ShakeEffect({
    Duration? delay,
    Duration? duration,
    Curve? curve,
    int count = 3,
    this.offset = Offset.zero,
    this.rotation = pi / 36,
  }) : super(
          delay: delay,
          duration: duration,
          curve: curve,
          begin: 0,
          end: count * pi * 2,
        );

  final Offset offset;
  final double rotation;

  @override
  Widget build(
    BuildContext context,
    Widget child,
    AnimationController controller,
    EffectEntry entry,
  ) {
    bool shouldRotate = rotation != 0;
    bool shouldTranslate = offset != Offset.zero;
    if (!shouldRotate && !shouldTranslate) return child;

    Animation<double> animation = buildAnimation(controller, entry);
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        double a = sin(animation.value);
        if (shouldRotate) {
          child = Transform.rotate(angle: rotation * a, child: child);
        }
        if (shouldTranslate) {
          child = Transform.translate(offset: offset * a, child: child);
        }
        return child;
      },
    );
  }
}

extension ShakeEffectExtensions<T> on AnimateManager<T> {
  /// Adds a `.shake()` extension to [AnimateManager] ([Animate] and [AnimateList]).
  T shake({
    Duration? delay,
    Duration? duration,
    Curve? curve,
    int count = 3,
    Offset offset = Offset.zero,
    double rotation = pi / 36,
  }) =>
      addEffect(ShakeEffect(
        delay: delay,
        duration: duration,
        curve: curve,
        count: count,
        offset: offset,
        rotation: rotation,
      ));

  /// Adds a `.shakeX()` extension to [AnimateManager] ([Animate] and [AnimateList]).
  T shakeX({
    Duration? delay,
    Duration? duration,
    Curve? curve,
    int count = 3,
    double amount = 6,
  }) =>
      addEffect(ShakeEffect(
        delay: delay,
        duration: duration,
        curve: curve,
        count: count,
        offset: Offset(amount, 0),
        rotation: 0,
      ));

  /// Adds a `.shakeY()` extension to [AnimateManager] ([Animate] and [AnimateList]).
  T shakeY({
    Duration? delay,
    Duration? duration,
    Curve? curve,
    int count = 3,
    double amount = 6,
  }) =>
      addEffect(ShakeEffect(
        delay: delay,
        duration: duration,
        curve: curve,
        count: count,
        offset: Offset(0, amount),
        rotation: 0,
      ));
}
