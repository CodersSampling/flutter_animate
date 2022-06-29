import 'package:flutter/widgets.dart';
import 'flutter_animate.dart';

// TODO: do a full pass on widget lifecycle support. Possibly params to reset on change?

/// The Flutter Animate library makes adding beautiful animated effects to your widgets
/// simple. It supports both a declarative and chained API. The latter is exposed
/// via the `Widget.animate` extension, which simply wraps the widget in `Animate`.
///
/// ```
/// // declarative:
/// Animate(child: foo, effects: [FadeEffect(), ScaleEffect()])
/// // equivalent chained API:
/// foo.animate().fade().scale() // equivalent to above
/// ```
///
/// Effects are always run in parallel (ie. the fade and scale effects in the
/// example above would be run simultaneously), but you can apply delays to
/// offset them or run them in sequence.
///
/// All effects classes are immutable, and can be shared between `Animate`
/// instances, which lets you create libraries of effects to reuse throughout
/// your app.
///
/// ```
/// List<Effect> transitionIn = [
///   FadeEffect(duration: 100.ms, curve: Curves.easeOut),
///   ScaleEffect(begin: 0.8, curve: Curves.easeIn)
/// ];
/// // then:
/// Animate(child: foo, effects: transitionIn)
/// // or:
/// foo.animate(effects: transitionIn)
/// ```
///
/// Effects inherit some of their properties (delay, duration, curve) from the
/// previous effect if unspecified. So in the examples above, the scale will use
/// the same duration as the fade that precedes it. All effects have
/// reasonable defaults, so they can be used simply: `foo.animate().fade()`
///
/// Note that all effects are composed together, not run sequentially. For example,
/// the following would not fade in myWidget, because the fadeOut effect would still be
/// applying an opacity of 0:
///
/// ```
/// myWidget.animate().fadeOut(duration: 200.ms).fadeIn(delay: 200.ms)
/// ```
///
/// See [SwapEffect] for one approach to work around this.

// ignore: must_be_immutable
class Animate extends StatefulWidget with AnimateManager<Animate> {
  /// Default duration for effects.
  static Duration defaultDuration = const Duration(milliseconds: 300);

  /// Default curve for effects.
  static Curve defaultCurve = Curves.linear;

  /// Widget types to reparent, mapped to a method that handles that type. This is used
  /// to make it easy to work with widgets that require specific parents. For example,
  /// the [Positioned] widget, which needs its immediate parent to be a [Stack].
  ///
  /// Handles [Flexible], [Positioned], and [Expanded] by default, but you can add additional
  /// handlers as appropriate. Example, this would add support for a hypothetical
  /// "AlignPositioned" widget, that has an `alignment` property.
  ///
  /// ```
  /// Animate.reparentTypes[AlignPositioned] = (parent, child) {
  ///   AlignPositioned o = parent as AlignPositioned;
  ///   return AlignPositioned(alignment: o.alignment, child: child);
  /// }
  /// ```
  static Map reparentTypes = <Type, ReparentChildBuilder>{
    Flexible: (parent, child) {
      Flexible o = parent as Flexible;
      return Flexible(key: o.key, flex: o.flex, fit: o.fit, child: child);
    },
    Positioned: (parent, child) {
      Positioned o = parent as Positioned;
      return Positioned(
        key: o.key,
        left: o.left,
        top: o.top,
        right: o.right,
        bottom: o.bottom,
        width: o.width,
        height: o.height,
        child: child,
      );
    },
    Expanded: (parent, child) {
      Expanded o = parent as Expanded;
      return Expanded(key: o.key, flex: o.flex, child: child);
    }
  };

  /// Creates an Animate instance that will manage a list of effects and apply
  /// them to the specified child.
  Animate({
    Key? key,
    this.child = const SizedBox.shrink(),
    List<Effect>? effects,
    this.onInit,
    this.onPlay,
    this.onComplete,
    this.delay = Duration.zero,
    this.controller,
    this.adapter,
  }) : super(key: key) {
    _entries = [];
    if (effects != null) addEffects(effects);
  }

  /// The widget to apply effects to.
  final Widget child;

  /// Called when the [AnimationController] for this instance is initialized,
  /// but before it starts playing.
  /// 
  /// This typically occurs once when the widget [State] is created, but can
  /// also happen if the widget is updated with a new [controller].
  /// 
  /// Can be used to (for example) loop or reverse
  /// the animation, but cannot be used to adjust its starting postion or 
  /// pause it because `AnimationController.forward(from: 0)` is called after
  /// `onInit` – use [onPlay] instead.
  /// 
  /// This would loop the animation, reversing it on each loop:
  /// ```
  /// foo.animate(
  ///   onInit: (controller) => controller.repeat(reverse: true)
  /// ).fadeIn()
  /// ```
  final AnimateCallback? onInit;

  /// Called when the animation begins playing (ie. immediately after
  /// [AnimationController.forward] is called after [delay]).
  /// Provides an opportunity to manipulate the [AnimationController]
  /// (ex. to loop, reverse, stop, change starting position, etc).
  /// 
  /// For example, this would pause the animation at its start:
  /// ```
  /// foo.animate(
  ///   onPlay: (controller) => controller.stop()
  /// ).fadeIn()
  /// ```
  final AnimateCallback? onPlay;

  /// Called when all effects complete (ie. the [AnimationController] status
  /// is [AnimationStatus.completed]). A looping animation will never call 
  /// `onComplete`.
  final AnimateCallback? onComplete;

  /// A duration to delay before the animation is started. Unlike [Effect.delay],
  /// this is not a part of the overall animation, and only runs once if the
  /// animation is looped. [onInit] is called after this delay.
  final Duration delay;

  /// An external [AnimationController] can optionally be specified. By default
  /// Animate creates its own controller internally.
  final AnimationController? controller;

  /// An [Adapter] can drive the animation from an external source (ex. a [ScrollController],
  /// [ValueNotifier], or arbitrary `0-1` value). For more information see [Adapter]
  /// or an adapter class ([ChangeNotifierAdapter], [ScrollAdapter], [ValueAdapter],
  /// [ValueNotifierAdapter]).
  ///
  /// If an adapter is provided, then [delay] is ignored, and you should not
  /// make changes to the [AnimationController] directly (ex. via [onInit])
  /// because it can cause unexpected results.
  final Adapter? adapter;

  late final List<EffectEntry> _entries;
  Duration _duration = Duration.zero;
  EffectEntry? _lastEntry;

  /// The total duration for all effects.
  Duration get duration => _duration;

  @override
  State<Animate> createState() => _AnimateState();

  /// Adds an effect. This is mostly used by [Effect] extension methods to append effects
  /// to an [Animate] instance.
  @override
  Animate addEffect(Effect effect) {
    EffectEntry? prior = _lastEntry;

    Duration delay = (effect is ThenEffect)
        ? (effect.delay ?? Duration.zero) +
            (prior?.delay ?? Duration.zero) +
            (prior?.duration ?? Duration.zero)
        : effect.delay ?? prior?.delay ?? Duration.zero;

    EffectEntry entry = EffectEntry(
      effect: effect,
      delay: delay,
      duration: effect.duration ?? prior?.duration ?? Animate.defaultDuration,
      curve: effect.curve ?? prior?.curve ?? Animate.defaultCurve,
      owner: this,
    );

    _entries.add(entry);
    _lastEntry = entry;
    if (entry.end > _duration) _duration = entry.end;
    return this;
  }
}

class _AnimateState extends State<Animate> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isInternalController = false;
  bool _hasAdapter = false;
  Future<void>? _delayed;

  @override
  void initState() {
    super.initState();
    _initController();
    if (!_hasAdapter) _delayed = Future.delayed(widget.delay, () => _play());
  }

  @override
  void didUpdateWidget(Animate oldWidget) {
    if (oldWidget.controller != widget.controller) {
      _initController();
    } else if (oldWidget.adapter != widget.adapter) {
      _initAdapter();
    }
    super.didUpdateWidget(oldWidget);
  }

  void _initController() {
    AnimationController? controller;

    if (widget.controller != null) {
      // externally provided AnimationController.
      controller = widget.controller!;
      _isInternalController = false;
    } else if (!_isInternalController) {
      // create a new internal AnimationController.
      controller = AnimationController(vsync: this);
      _isInternalController = true;
    } else {
      // pre-existing controller
      return;
    }

    // new controller.
    controller.duration ??= widget._duration;
    controller.addStatusListener(_handleAnimationStatus);
    _controller = controller;
    _initAdapter();
    widget.onInit?.call(_controller);
  }

  void _initAdapter() {
    final Adapter? adapter = widget.adapter;
    _hasAdapter = adapter != null;
    adapter?.init(_controller);
  }

  void _disposeController() {
    if (_isInternalController) _controller.dispose();
    _isInternalController = false;
  }

  @override
  void dispose() {
    _delayed?.ignore();
    _disposeController();
    super.dispose();
  }

  void _handleAnimationStatus(status) {
    if (status == AnimationStatus.completed) {
      widget.onComplete?.call(_controller);
    }
  }

  void _play() {
    if (!_hasAdapter) _controller.forward(from: 0);
    widget.onPlay?.call(_controller);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child, parent = child;
    ReparentChildBuilder? reparent = Animate.reparentTypes[child.runtimeType];
    if (reparent != null) child = (child as dynamic).child;
    for (EffectEntry entry in widget._entries) {
      child = entry.effect.build(context, child, _controller, entry);
    }
    return reparent?.call(parent, child) ?? child;
  }
}

/// Wraps the target Widget in an Animate instance. Ex. `myWidget.animate()` is equivalent
/// to `Animate(child: myWidget)`.
extension AnimateWidgetExtensions on Widget {
  Animate animate({
    Key? key,
    List<Effect>? effects,
    AnimateCallback? onComplete,
    AnimateCallback? onInit,
    Duration delay = Duration.zero,
    AnimationController? controller,
    Adapter? adapter,
  }) =>
      Animate(
        key: key,
        effects: effects,
        onComplete: onComplete,
        onInit: onInit,
        delay: delay,
        controller: controller,
        adapter: adapter,
        child: this,
      );
}

/// The builder type used by [Animate.reparentTypes]. It must accept an existing
/// parent widget, and rebuild it with the provided child. In effect, it clones
/// the provided parent widget with the new child.
typedef ReparentChildBuilder = Widget Function(Widget parent, Widget child);

/// Function signature for [Animate] callbacks.
typedef AnimateCallback = void Function(AnimationController controller);
