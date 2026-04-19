import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/stream_configuration.dart';
import '../providers/theme_provider.dart';

String _tr(BuildContext context, String en, String es) =>
    AppLocalizations.of(context).locale.languageCode == 'es' ? es : en;

// Semantic chart colours — calm tones, not neon
const _kFpsClr = Color(0xFF30D158); // Apple system green
const _kDecodeClr = Color(0xFFFF9F0A); // Apple system orange
const _kBitrateClr = Color(0xFF0A84FF); // Apple system blue
const _kDropClr = Color(0xFFFF453A); // Apple system red

// White palette literals (avoids theme helpers for readability guarantee)
const _kW0 = Colors.white; // primary  100%
const _kW2 = Color(0x99FFFFFF); // muted     60%
const _kW3 = Color(0x66FFFFFF); // faint     40%

class SessionMetricPoint {
  final int second;
  final int fps;
  final int decodeMs;
  final int bitrateMbps;
  final int dropRate;

  const SessionMetricPoint({
    required this.second,
    required this.fps,
    required this.decodeMs,
    required this.bitrateMbps,
    required this.dropRate,
  });
}

class SessionMetricsDialog extends StatefulWidget {
  final String appName;
  final List<SessionMetricPoint> points;
  final StreamConfiguration? config;
  // actual decoder used during stream (e.g. 'AV1', 'HEVC', 'H264')
  final String? decoder;

  const SessionMetricsDialog({
    super.key,
    required this.appName,
    required this.points,
    this.config,
    this.decoder,
  });

  @override
  State<SessionMetricsDialog> createState() => _SessionMetricsDialogState();
}

class _SessionMetricsDialogState extends State<SessionMetricsDialog>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _repaintKey = GlobalKey();
  late final AnimationController _animCtrl;
  late final Animation<double> _cardAnim;
  late final Animation<double> _chartAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _cardAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
    );
    _chartAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_scrollCtrl.hasClients) return;
    final target = (_scrollCtrl.offset + delta).clamp(
      0.0,
      _scrollCtrl.position.maxScrollExtent,
    );
    _scrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  String _buildSummary(BuildContext context) {
    final pts = widget.points;
    final durationSec = pts.isEmpty ? 0 : pts.last.second + 1;
    final avgFps = _avg(pts.map((p) => p.fps));
    final avgBitrate = _avg(pts.map((p) => p.bitrateMbps));
    return '${_tr(context, 'Session', 'Sesion')}: ${widget.appName} • ${_fmtDur(durationSec)} • ${_tr(context, 'Avg', 'Prom')} FPS ${avgFps.round()} • ${avgBitrate.round()} Mbps — JUJO Stream';
  }

  void _shareSummary(BuildContext context) async {
    try {
      final boundary =
          _repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}/jujo_metrics.png');
      await file.writeAsBytes(pngBytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: _buildSummary(context)),
      );
    } catch (_) {
      // graceful fallback to text
      SharePlus.instance.share(ShareParams(text: _buildSummary(context)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final size = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final safeWidth = math.max(280.0, size.width - 20);
    final safeHeight = math.max(320.0, size.height - safePadding.vertical - 12);
    final dialogWidth = math.min(560.0, safeWidth);
    final compactLayout = dialogWidth < 430 || safeHeight < 760;

    final points = widget.points;
    final durationSec = points.isEmpty ? 0 : points.last.second + 1;
    final avgFps = _avg(points.map((p) => p.fps));
    final avgDecode = _avg(points.map((p) => p.decodeMs));
    final avgBitrate = _avg(points.map((p) => p.bitrateMbps));
    final maxDrop = points.fold<int>(0, (b, p) => math.max(b, p.dropRate));
    final peakDecode = points.fold<int>(0, (b, p) => math.max(b, p.decodeMs));
    final c = widget.config;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Align(
        alignment: Alignment.center,
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final k = event.logicalKey;
            if (k == LogicalKeyboardKey.gameButtonB ||
                k == LogicalKeyboardKey.escape ||
                k == LogicalKeyboardKey.goBack) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.arrowDown) {
              _scrollBy(100);
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.arrowUp) {
              _scrollBy(-100);
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.gameButtonY) {
              _shareSummary(context);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: RepaintBoundary(
            key: _repaintKey,
            child: Container(
              width: dialogWidth,
              decoration: BoxDecoration(
                color: tp.surface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: safeHeight),
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: EdgeInsets.fromLTRB(
                      compactLayout ? 12 : 16,
                      compactLayout ? 12 : 14,
                      compactLayout ? 12 : 16,
                      compactLayout ? 12 : 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _tr(
                                      context,
                                      'Session Metrics',
                                      'Metricas de sesion',
                                    ),
                                    style: const TextStyle(
                                      color: _kW0,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.appName,
                                    style: const TextStyle(
                                      color: _kW0,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _shareSummary(context),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.ios_share_rounded,
                                      color: _kW2,
                                      size: 17,
                                    ),
                                    const SizedBox(width: 2),
                                    Opacity(
                                      opacity: 0.55,
                                      child: Image.asset(
                                        'assets/images/UI/xbox/button_xbox_digital_y.png',
                                        width: 16,
                                        height: 16,
                                        filterQuality: FilterQuality.medium,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: _kW2,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (c != null) ...[
                          const SizedBox(height: 6),
                          _buildConfigStrip(c),
                        ],
                        const SizedBox(height: 8),
                        Divider(
                          color: Colors.white.withValues(alpha: 0.07),
                          height: 1,
                        ),
                        const SizedBox(height: 10),
                        FadeTransition(
                          opacity: _cardAnim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.12),
                              end: Offset.zero,
                            ).animate(_cardAnim),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _SummaryCard(
                                    label: _tr(context, 'Duration', 'Duracion'),
                                    value: _fmtDur(durationSec),
                                    accent: _kW0,
                                    bg: tp.background,
                                  ),
                                  const SizedBox(width: 9),
                                  _SummaryCard(
                                    label: _tr(context, 'Avg FPS', 'FPS prom.'),
                                    value: '${avgFps.round()}',
                                    accent: _kFpsClr,
                                    bg: tp.background,
                                  ),
                                  const SizedBox(width: 9),
                                  _SummaryCard(
                                    label: _tr(
                                      context,
                                      'Avg Decode',
                                      'Dec. prom.',
                                    ),
                                    value: '${avgDecode.round()} ms',
                                    accent: _kDecodeClr,
                                    bg: tp.background,
                                  ),
                                  const SizedBox(width: 9),
                                  _SummaryCard(
                                    label: _tr(
                                      context,
                                      'Peak Decode',
                                      'Dec. pico',
                                    ),
                                    value: '$peakDecode ms',
                                    accent: peakDecode > 50
                                        ? _kDropClr
                                        : _kDecodeClr,
                                    bg: tp.background,
                                  ),
                                  const SizedBox(width: 9),
                                  _SummaryCard(
                                    label: 'Bitrate',
                                    value: '${avgBitrate.round()} Mbps',
                                    accent: _kBitrateClr,
                                    bg: tp.background,
                                  ),
                                  const SizedBox(width: 9),
                                  _SummaryCard(
                                    label: _tr(
                                      context,
                                      'Peak Drop',
                                      'Pico perd.',
                                    ),
                                    value: '$maxDrop%',
                                    accent: maxDrop > 5 ? _kDropClr : _kW0,
                                    bg: tp.background,
                                  ),
                                  if (widget.decoder != null &&
                                      widget.decoder!.isNotEmpty) ...[
                                    const SizedBox(width: 9),
                                    _SummaryCard(
                                      label: _tr(
                                        context,
                                        'Decoder',
                                        'Decodif.',
                                      ),
                                      value: widget.decoder!,
                                      accent: const Color(0xFFA78BFA),
                                      bg: tp.background,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        AnimatedBuilder(
                          animation: _chartAnim,
                          builder: (context, _) {
                            final p = _chartAnim.value;
                            return Opacity(
                              opacity: p.clamp(0.0, 1.0),
                              child: _buildChartsGrid(
                                compactLayout: compactLayout,
                                drawProgress: p,
                                tp: tp,
                                points: points,
                                avgFps: avgFps,
                                avgDecode: avgDecode,
                                avgBitrate: avgBitrate,
                                maxDrop: maxDrop,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartsGrid({
    required bool compactLayout,
    required double drawProgress,
    required ThemeProvider tp,
    required List<SessionMetricPoint> points,
    required double avgFps,
    required double avgDecode,
    required double avgBitrate,
    required int maxDrop,
  }) {
    final fpsPanel = _MiniPanel(
      title: 'FPS',
      badge: '${avgFps.round()} avg',
      color: _kFpsClr,
      pts: points.map((p) => p.fps.toDouble()).toList(),
      bg: tp.background,
      drawProgress: drawProgress,
    );
    final decodePanel = _MiniPanel(
      title: 'Decode',
      badge: '${avgDecode.round()} ms avg',
      color: _kDecodeClr,
      pts: points.map((p) => p.decodeMs.toDouble()).toList(),
      bg: tp.background,
      drawProgress: drawProgress,
    );
    final bitratePanel = _MiniPanel(
      title: 'Bitrate',
      badge: '${avgBitrate.round()} Mbps avg',
      color: _kBitrateClr,
      pts: points.map((p) => p.bitrateMbps.toDouble()).toList(),
      bg: tp.background,
      drawProgress: drawProgress,
    );
    final isDropStable = maxDrop <= 1;
    final dropPanel = _MiniPanel(
      title: _tr(context, 'Drop %', 'Perdida %'),
      badge: isDropStable
          ? _tr(context, 'Stable', 'Estable')
          : '$maxDrop% peak',
      color: _kDropClr,
      pts: points.map((p) => p.dropRate.toDouble()).toList(),
      maxY: 100,
      bg: tp.background,
      drawProgress: drawProgress,
      sparkline: isDropStable,
    );

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: fpsPanel),
            const SizedBox(width: 9),
            Expanded(child: decodePanel),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(child: bitratePanel),
            const SizedBox(width: 9),
            Expanded(child: dropPanel),
          ],
        ),
      ],
    );
  }

  Widget _buildConfigStrip(StreamConfiguration c) {
    final codecLabel = switch (c.videoCodec) {
      VideoCodec.h264 => 'H.264',
      VideoCodec.h265 => 'HEVC',
      VideoCodec.av1 => 'AV1',
      VideoCodec.auto => 'Auto',
    };
    final bitrateLabel = c.smartBitrateEnabled
        ? '${(c.smartBitrateMin / 1000).round()}-${(c.smartBitrateMax / 1000).round()} Mbps'
        : '${(c.bitrate / 1000).round()} Mbps';
    final latencyLabel = c.ultraLowLatency
        ? 'Ultra Low'
        : switch (c.framePacing) {
            FramePacing.latency => 'Low Latency',
            FramePacing.balanced => 'Balanced',
            FramePacing.capFps => 'Cap FPS',
            FramePacing.smoothness => 'Smooth',
            FramePacing.adaptive => 'Adaptive',
          };
    final decoderLabel = widget.decoder != null && widget.decoder!.isNotEmpty
        ? widget.decoder!
        : null;
    final items = <(IconData, String)>[
      (Icons.videocam_outlined, decoderLabel ?? codecLabel),
      (Icons.speed_outlined, '${c.fps} FPS'),
      (Icons.wifi_outlined, bitrateLabel),
      (Icons.aspect_ratio_outlined, '${c.width}x${c.height}'),
      (Icons.timer_outlined, latencyLabel),
      if (c.enableHdr) (Icons.hdr_on_outlined, 'HDR'),
    ];
    return Wrap(
      spacing: 18,
      runSpacing: 5,
      children: items
          .map(
            (e) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(e.$1, size: 12, color: _kW3),
                const SizedBox(width: 4),
                Text(
                  e.$2,
                  style: const TextStyle(
                    color: _kW2,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  static double _avg(Iterable<int> vals) {
    if (vals.isEmpty) return 0;
    return vals.fold<int>(0, (s, v) => s + v) / vals.length;
  }

  static String _fmtDur(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return m == 0 ? '${s}s' : '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

// ─── Summary card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final Color bg;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 64),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _kW3,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mini chart panel (2-column grid) ─────────────────────────────────────────

class _MiniPanel extends StatelessWidget {
  final String title;
  final String badge;
  final Color color;
  final List<double> pts;
  final double? maxY;
  final Color bg;
  final double drawProgress;
  final bool sparkline;

  const _MiniPanel({
    required this.title,
    required this.badge,
    required this.color,
    required this.pts,
    required this.bg,
    this.maxY,
    this.drawProgress = 1.0,
    this.sparkline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _kW0,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 82,
            width: double.infinity,
            child: CustomPaint(
              painter: _ChartPainter(
                points: pts,
                color: color,
                maxY: maxY,
                drawProgress: drawProgress,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chart painter ────────────────────────────────────────────────────────────

class _ChartPainter extends CustomPainter {
  final List<double> points;
  final Color color;
  final double? maxY;
  final double drawProgress;

  const _ChartPainter({
    required this.points,
    required this.color,
    this.maxY,
    this.drawProgress = 1.0,
  });

  // ── Axis label helpers ──────────────────────────────────────────

  static String _fmtVal(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    if (v >= 100) return v.round().toString();
    if (v >= 10) return v.round().toString();
    if (v >= 1) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  static String _fmtSec(int sec) {
    if (sec == 0) return '0';
    if (sec < 60) return '${sec}s';
    final m = sec ~/ 60;
    final s = sec % 60;
    return s == 0 ? '${m}m' : '${m}:${s.toString().padLeft(2, '0')}';
  }

  static const _kLabelStyle = TextStyle(
    color: Color(0x73FFFFFF),
    fontSize: 7.5,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static void _drawLabel(
    Canvas canvas,
    String text,
    double x,
    double y, {
    bool rightAlign = false,
    bool centerAlign = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _kLabelStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 40);
    final dx = rightAlign
        ? x - tp.width
        : centerAlign
        ? x - tp.width / 2
        : x;
    tp.paint(canvas, Offset(dx, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Bottom area reserved for X axis labels.
    const xLabelH = 12.0;
    final chartH = size.height - xLabelH;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 1; i < 4; i++) {
      final y = chartH * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Compute range (needed for Y labels even when list is empty).
    final effectiveMax =
        maxY ?? (points.isEmpty ? 1.0 : math.max(points.reduce(math.max), 1.0));
    final effectiveMin = points.isEmpty
        ? 0.0
        : math.min(0.0, points.reduce(math.min));
    final range = math.max(1.0, effectiveMax - effectiveMin);

    // ── Y axis labels at the 3 horizontal gridlines ─────────────────
    for (var i = 1; i <= 3; i++) {
      final frac = i / 4.0; // 0.25, 0.50, 0.75 from top
      final value = effectiveMax - (range * frac);
      if (value < 0) continue;
      final yPos = chartH * frac;
      // Draw right-aligned against the left edge (x = 0) offset up by ~8.5px.
      _drawLabel(canvas, _fmtVal(value), 0, yPos - 8.5);
    }

    if (points.isEmpty || drawProgress <= 0) return;

    // Clip to reveal only the drawn portion (chart area only, not labels).
    final clipW = size.width * drawProgress.clamp(0.0, 1.0);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, clipW, chartH));

    final stepX = points.length == 1
        ? size.width
        : size.width / (points.length - 1);

    final path = Path();
    final fill = Path();

    for (var i = 0; i < points.length; i++) {
      final x = stepX * i;
      final normalized = (points[i] - effectiveMin) / range;
      final y = chartH - (normalized * (chartH - 6)) - 3;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, chartH);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill
      ..lineTo(size.width, chartH)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, chartH))
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final lastNorm = (points.last - effectiveMin) / range;
    final lastY = chartH - (lastNorm * (chartH - 6)) - 3;
    canvas.drawCircle(Offset(size.width, lastY), 3.2, Paint()..color = color);
    canvas.restore();

    // ── X axis labels (time) — drawn after restore to stay on top ────
    if (points.length > 1) {
      final totalSec = points.length - 1;
      final yLabel = chartH + 2.0;
      // Left: 0
      _drawLabel(canvas, '0', 0, yLabel);
      // Right: total duration
      _drawLabel(
        canvas,
        _fmtSec(totalSec),
        size.width,
        yLabel,
        rightAlign: true,
      );
      // Mid: only when session is long enough to be worth showing
      if (totalSec >= 20) {
        _drawLabel(
          canvas,
          _fmtSec(totalSec ~/ 2),
          size.width / 2,
          yLabel,
          centerAlign: true,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.points != points ||
      old.color != color ||
      old.maxY != maxY ||
      old.drawProgress != drawProgress;
}
