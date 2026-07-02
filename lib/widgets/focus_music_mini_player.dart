import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/theme_config.dart';

const _mingcuteMusic3FillSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24"><g fill="none"><path d="m12.593 23.258l-.011.002l-.071.035l-.02.004l-.014-.004l-.071-.035q-.016-.005-.024.005l-.004.01l-.017.428l.005.02l.01.013l.104.074l.015.004l.012-.004l.104-.074l.012-.016l.004-.017l-.017-.427q-.004-.016-.017-.018m.265-.113l-.013.002l-.185.093l-.01.01l-.003.011l.018.43l.005.012l.008.007l.201.093q.019.005.029-.008l.004-.014l-.034-.614q-.005-.018-.02-.022m-.715.002a.02.02 0 0 0-.027.006l-.006.014l-.034.614q.001.018.017.024l.015-.002l.201-.093l.01-.008l.004-.011l.017-.43l-.003-.012l-.01-.01z"/><path fill="currentColor" d="M10.414 3.012A1.5 1.5 0 0 1 9.5 4.926A7.5 7.5 0 1 0 19.5 12c0-1.2-.28-2.33-.779-3.332a1.5 1.5 0 0 1 2.687-1.336A10.46 10.46 0 0 1 22.5 12c0 5.799-4.701 10.5-10.5 10.5S1.5 17.799 1.5 12c0-4.574 2.924-8.461 7-9.902a1.5 1.5 0 0 1 1.914.914m2.086.002a1.51 1.51 0 0 1 1.86-1.47l.128.037l2.986.996a1.5 1.5 0 0 1-.81 2.885l-.138-.039l-1.026-.342V12l-.005.192a3.5 3.5 0 1 1-3.16-3.676l.165.02z"/></g></svg>';

class FocusMusicMiniPlayer extends StatelessWidget {
  final String trackName;
  final AppThemeColors? colors;
  final double scale;
  final double opacity;

  const FocusMusicMiniPlayer({
    super.key,
    required this.trackName,
    this.colors,
    this.scale = 1.0,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors ?? AppThemes.presets[AppThemeId.oled]!;
    final fg = c.isLight ? Colors.black87 : Colors.white;
    final sub = c.isLight ? Colors.black54 : Colors.white70;
    final effectiveScale = scale.clamp(0.40, 1.50);
    final effectiveOpacity = opacity.clamp(0.20, 1.00);
    final bg = c.surfaceVariant.withValues(
      alpha: (c.isLight ? 0.88 : 0.86) * effectiveOpacity,
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 236 * effectiveScale,
        height: 66 * effectiveScale,
        padding: EdgeInsets.fromLTRB(
          10 * effectiveScale,
          9 * effectiveScale,
          14 * effectiveScale,
          9 * effectiveScale,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(86),
          border: Border.all(color: c.accent.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: (c.isLight ? 0.10 : 0.28) * effectiveOpacity,
              ),
              blurRadius: 22 * effectiveScale,
              offset: Offset(0, 10 * effectiveScale),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48 * effectiveScale,
              height: 48 * effectiveScale,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.accent.withValues(alpha: c.isLight ? 0.18 : 0.24),
              ),
              child: SvgPicture.string(
                _mingcuteMusic3FillSvg,
                width: 27 * effectiveScale,
                height: 27 * effectiveScale,
                colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
              ),
            ),
            SizedBox(width: 12 * effectiveScale),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NOW PLAYING',
                    maxLines: 1,
                    style: TextStyle(
                      color: fg,
                      fontSize: 10 * effectiveScale,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  SizedBox(height: 5 * effectiveScale),
                  ScrollingOverflowText(
                    text: trackName,
                    style: TextStyle(
                      color: sub,
                      fontSize: 12 * effectiveScale,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScrollingOverflowText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const ScrollingOverflowText({super.key, required this.text, this.style});

  @override
  State<ScrollingOverflowText> createState() => _ScrollingOverflowTextState();
}

class _ScrollingOverflowTextState extends State<ScrollingOverflowText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(ScrollingOverflowText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: double.infinity);

        final textWidth = painter.width;
        final maxWidth = constraints.maxWidth;
        if (textWidth <= maxWidth) {
          _stopIfNeeded();
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }

        final distance = textWidth - maxWidth + math.min(24.0, maxWidth * 0.15);
        _startIfNeeded(distance);

        return ClipRect(
          child: SizedBox(
            width: maxWidth,
            height: painter.height,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Transform.translate(
                  offset: Offset(-distance * _controller.value, 0),
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: textWidth,
                    child: SizedBox(
                      width: textWidth,
                      child: Text(widget.text, maxLines: 1, style: style),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _startIfNeeded(double distance) {
    final duration = Duration(
      milliseconds: math.max(4500, (distance * 36).round()),
    );
    if (_controller.isAnimating && _controller.duration == duration) return;
    _controller
      ..duration = duration
      ..repeat(reverse: true);
  }

  void _stopIfNeeded() {
    if (!_controller.isAnimating && _controller.value == 0) return;
    _controller
      ..stop()
      ..reset();
  }
}
