import 'dart:math' as math;
import 'package:flutter/material.dart';

class ReportChartCard extends StatelessWidget {
  const ReportChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title, subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 18),
          SizedBox(height: 190, width: double.infinity, child: child),
        ],
      ),
    ),
  );
}

class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({super.key, required this.values, required this.labels});
  final List<double> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BarPainter(values, labels));
}

class SimpleLineChart extends StatelessWidget {
  const SimpleLineChart({super.key, required this.values});
  final List<double> values;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _LinePainter(values));
}

class SimplePieChart extends StatelessWidget {
  const SimplePieChart({super.key, required this.values, required this.labels});
  final List<double> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PiePainter(values, labels));
}

class _BarPainter extends CustomPainter {
  const _BarPainter(this.values, this.labels);
  final List<double> values;
  final List<String> labels;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = math.max(1.0, values.reduce(math.max));
    final count = math.min(values.length, 8);
    final slot = size.width / count;
    final paint = Paint()..color = const Color(0xFF17665B);
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < count; i++) {
      final height = (size.height - 34) * (values[i] / maxValue);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * slot + 7,
          size.height - 26 - height,
          slot - 14,
          height,
        ),
        const Radius.circular(6),
      );
      canvas.drawRRect(rect, paint);
      text.text = TextSpan(
        text: labels[i].length > 7
            ? '${labels[i].substring(0, 7)}…'
            : labels[i],
        style: const TextStyle(fontSize: 9, color: Color(0xFF60716D)),
      );
      text.layout(maxWidth: slot - 4);
      text.paint(canvas, Offset(i * slot + 3, size.height - 18));
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.values != values;
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final axis = Paint()..color = const Color(0xFFDDE6E3);
    for (var i = 0; i < 4; i++) {
      final y = i * (size.height - 18) / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), axis);
    }
    final maxValue = math.max(1.0, values.reduce(math.max));
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : i * size.width / (values.length - 1);
      final y = size.height - 20 - (size.height - 30) * values[i] / maxValue;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF17665B)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values;
}

class _PiePainter extends CustomPainter {
  const _PiePainter(this.values, this.labels);
  final List<double> values;
  final List<String> labels;
  static const colors = [
    Color(0xFF17665B),
    Color(0xFFE0A84B),
    Color(0xFF5E7596),
    Color(0xFFC9655A),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final center = Offset(size.width * .3, size.height / 2);
    final rect = Rect.fromCircle(
      center: center,
      radius: math.min(68, size.height * .4),
    );
    var start = -math.pi / 2;
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < values.length; i++) {
      final sweep = math.pi * 2 * values[i] / total;
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()..color = colors[i % colors.length],
      );
      start += sweep;
      if (i < labels.length) {
        canvas.drawCircle(
          Offset(size.width * .62, 24.0 + i * 32),
          6,
          Paint()..color = colors[i % colors.length],
        );
        text.text = TextSpan(
          text: '${labels[i]} (${values[i].round()})',
          style: const TextStyle(fontSize: 11, color: Color(0xFF314541)),
        );
        text.layout(maxWidth: size.width * .34);
        text.paint(canvas, Offset(size.width * .66, 17.0 + i * 32));
      }
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.values != values;
}
