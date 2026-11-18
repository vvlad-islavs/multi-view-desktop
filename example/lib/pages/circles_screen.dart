import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

/// Dialog body from the Linux close report: an always-running painter that
/// draws 400 translucent circles. The raster thread stays busy until the
/// dialog is destroyed.
class CirclesScreen extends StatefulWidget {
  const CirclesScreen({super.key});

  @override
  State<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends State<CirclesScreen> with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _seconds.value = elapsed.inMicroseconds / 1000000.0;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF12161C),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _CirclesPainter(_seconds),
            child: const SizedBox.expand(),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton(
                onPressed: () => context.closeDialog<String>('Closed'),
                child: const Text('Close'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleSpec {
  const _CircleSpec({
    required this.nx,
    required this.ny,
    required this.radius,
    required this.phase,
    required this.speed,
    required this.color,
  });

  final double nx;
  final double ny;
  final double radius;
  final double phase;
  final double speed;
  final Color color;
}

class _CirclesPainter extends CustomPainter {
  _CirclesPainter(this.seconds) : super(repaint: seconds);

  final ValueNotifier<double> seconds;

  static final List<_CircleSpec> _circles = List<_CircleSpec>.generate(400, (i) {
    final random = math.Random(i * 9973);
    final hue = random.nextDouble() * 360;
    return _CircleSpec(
      nx: random.nextDouble(),
      ny: random.nextDouble(),
      radius: 8 + random.nextDouble() * 28,
      phase: random.nextDouble() * math.pi * 2,
      speed: 0.4 + random.nextDouble() * 1.6,
      color: HSVColor.fromAHSV(0.18 + random.nextDouble() * 0.35, hue, 0.55, 0.95).toColor(),
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = seconds.value;
    final paint = Paint();
    for (final circle in _circles) {
      final dx = math.sin(t * circle.speed + circle.phase) * 28;
      final dy = math.cos(t * circle.speed * 0.73 + circle.phase) * 22;
      paint.color = circle.color;
      canvas.drawCircle(
        Offset(circle.nx * size.width + dx, circle.ny * size.height + dy),
        circle.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CirclesPainter oldDelegate) => false;
}
