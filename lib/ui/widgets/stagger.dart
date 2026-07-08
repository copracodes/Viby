import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Hosts a single entrance [AnimationController] that runs **once** when it
/// mounts, and shares it (via an [InheritedWidget]) with descendant
/// [StaggeredEntrance] items. Because the controller runs once on first build,
/// lazily-built cells scrolled into view later see it already completed and
/// simply appear — so the stagger is limited to the first on-screen batch, not
/// every rebuild or scroll.
class StaggerScope extends StatefulWidget {
  const StaggerScope({super.key, required this.child});

  final Widget child;

  static Animation<double>? maybeOf(BuildContext context) {
    final _StaggerInherited? scope =
        context.dependOnInheritedWidgetOfExactType<_StaggerInherited>();
    return scope?.animation;
  }

  @override
  State<StaggerScope> createState() => _StaggerScopeState();
}

class _StaggerScopeState extends State<StaggerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StaggerInherited(animation: _controller, child: widget.child);
  }
}

class _StaggerInherited extends InheritedWidget {
  const _StaggerInherited({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_StaggerInherited oldWidget) => false;
}

/// Fades + rises its [child] into place, delayed by [index] × 30ms, using the
/// [StaggerScope]'s shared one-shot controller. Outside a scope (or once the
/// controller has finished) it renders the child immediately.
class StaggeredEntrance extends StatelessWidget {
  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
    this.staggerMs = 30,
  });

  final int index;
  final Widget child;
  final int staggerMs;

  @override
  Widget build(BuildContext context) {
    final Animation<double>? controller = StaggerScope.maybeOf(context);
    if (controller == null || controller.isCompleted) return child;

    const int totalMs = 700;
    const int itemMs = 300;
    final double start = ((index * staggerMs) / totalMs).clamp(0.0, 0.75);
    final double end = (start + itemMs / totalMs).clamp(0.0, 1.0);
    final Animation<double> t = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Motion.emphasizedDecelerate),
    );

    return AnimatedBuilder(
      animation: t,
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: t.value,
        child: Transform.translate(
          offset: Offset(0, (1 - t.value) * Spacing.lg),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
