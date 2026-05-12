import 'dart:async';

import 'package:flutter/material.dart';

class AlbumReveal extends StatefulWidget {
  const AlbumReveal({
    super.key,
    required this.delay,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
  });

  final Duration delay;
  final Duration duration;
  final Widget child;

  @override
  State<AlbumReveal> createState() => _AlbumRevealState();
}

class _AlbumRevealState extends State<AlbumReveal> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _visible = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class AlbumFadeOut extends StatefulWidget {
  const AlbumFadeOut({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
  });

  final Duration duration;
  final Widget child;

  @override
  State<AlbumFadeOut> createState() => _AlbumFadeOutState();
}

class _AlbumFadeOutState extends State<AlbumFadeOut> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _visible = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: widget.duration,
        curve: Curves.easeInCubic,
        child: widget.child,
      ),
    );
  }
}
