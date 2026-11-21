import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

import 'game.dart';

const _columnNames = 'ABCDEFGHJKLMNOPQRST';

String boardCoordinate(int size, int point) =>
    '${_columnNames[point % size]}${size - point ~/ size}';

class GoBoard extends StatelessWidget {
  const GoBoard({
    required this.position,
    required this.lastPoint,
    required this.selectedPoint,
    required this.onSelect,
    super.key,
  });

  final Position position;
  final int? lastPoint;
  final int? selectedPoint;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final grid = _Grid(constraints.maxWidth, position.size);
          return DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFE9BC7D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD6A668)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x182B2413),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTapUp: onSelect == null
                    ? null
                    : (details) {
                        final point = grid.pointAt(details.localPosition);
                        if (point != null) onSelect!(point);
                      },
                child: CustomPaint(
                  painter: _BoardPainter(
                    grid,
                    position,
                    lastPoint,
                    selectedPoint,
                    onSelect,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Grid {
  _Grid(this.width, this.size)
    : inset = (width * 0.062).clamp(16.0, 30.0),
      step = (width - 2 * (width * 0.062).clamp(16.0, 30.0)) / (size - 1);

  final double width;
  final int size;
  final double inset;
  final double step;

  Offset center(int x, int y) => Offset(inset + x * step, inset + y * step);

  int? pointAt(Offset offset) {
    final x = ((offset.dx - inset) / step).round();
    final y = ((offset.dy - inset) / step).round();
    if (x < 0 || x >= size || y < 0 || y >= size) return null;
    final delta = offset - center(x, y);
    if (delta.dx.abs() > step * 0.49 || delta.dy.abs() > step * 0.49) {
      return null;
    }
    return y * size + x;
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(
    this.grid,
    this.position,
    this.lastPoint,
    this.selectedPoint,
    this.onSelect,
  );

  final _Grid grid;
  final Position position;
  final int? lastPoint;
  final int? selectedPoint;
  final ValueChanged<int>? onSelect;

  @override
  void paint(Canvas canvas, Size size) {
    final wood = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        size.bottomRight(Offset.zero),
        const [Color(0xFFF4D59D), Color(0xFFE4B477)],
      );
    canvas.drawRect(Offset.zero & size, wood);

    final grain = Paint()
      ..color = const Color(0x0E855222)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    for (var y = 6; y < size.height; y += 8) {
      final bend = sin(y.toDouble()) * 3;
      final line = Path()
        ..moveTo(0, y.toDouble())
        ..cubicTo(
          size.width * 0.32,
          y + bend,
          size.width * 0.77,
          y - bend,
          size.width,
          y + 1,
        );
      canvas.drawPath(line, grain);
    }

    final count = grid.size;
    final line = Paint()
      ..color = const Color(0xFF765234)
      ..strokeWidth = 0.9;
    for (var i = 0; i < count; i++) {
      canvas.drawLine(grid.center(i, 0), grid.center(i, count - 1), line);
      canvas.drawLine(grid.center(0, i), grid.center(count - 1, i), line);
    }

    final mid = count ~/ 2;
    final edge = count == 9 ? 2 : 3;
    final axes = [edge, mid, count - 1 - edge];
    for (final y in axes) {
      for (final x in axes) {
        if (count == 9 && (x == mid) != (y == mid)) continue;
        canvas.drawCircle(grid.center(x, y), count == 19 ? 2 : 2.6, line);
      }
    }

    for (var i = 0; i < count; i++) {
      final column = _columnNames[i];
      final row = '${count - i}';
      _label(canvas, column, Offset(grid.center(i, 0).dx, grid.inset / 2));
      _label(canvas, row, Offset(grid.inset / 2, grid.center(0, i).dy));
    }

    for (var point = 0; point < position.stones.length; point++) {
      final stone = position.stones[point];
      if (stone == 0) continue;
      final center = grid.center(point % count, point ~/ count);
      _stone(canvas, center, stone == 1, point == lastPoint);
    }

    if (selectedPoint case final point?) {
      final center = grid.center(point % count, point ~/ count);
      _preview(canvas, center, occupied: position.stones[point] != 0);
    }
  }

  void _label(Canvas canvas, String text, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF63472D),
          fontSize: (grid.inset * 0.48).clamp(8.0, 12.0),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  void _stone(Canvas canvas, Offset center, bool black, bool isLast) {
    final radius = grid.step * 0.46;
    canvas.drawCircle(
      center.translate(0, radius * 0.12),
      radius,
      Paint()..color = const Color(0x500E140F),
    );
    final shade = Paint()
      ..shader = ui.Gradient.radial(
        center.translate(-radius * 0.34, -radius * 0.5),
        radius * 1.48,
        black
            ? const [Color(0xFF555952), Color(0xFF171A17)]
            : const [Color(0xFFFFFDF4), Color(0xFFDAD5C4)],
      );
    canvas.drawCircle(center, radius, shade);
    if (isLast) {
      canvas.drawCircle(
        center,
        radius * 0.32,
        Paint()
          ..color = black ? const Color(0xFFF4C278) : const Color(0xFF255241)
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.15, radius * 0.09),
      );
    }
  }

  void _preview(Canvas canvas, Offset center, {required bool occupied}) {
    final radius = grid.step * 0.43;
    if (!occupied) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = position.next == Stone.black
              ? const Color(0x88323A33)
              : const Color(0xBBFFF9E7),
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFF9F4E5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = occupied ? const Color(0xFF874625) : const Color(0xFF205F4B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (_) {
    final count = grid.size;
    return List.generate(count * count, (point) {
      final x = point % count;
      final y = point ~/ count;
      final label = switch (position.stones[point]) {
        1 => '黑棋',
        2 => '白棋',
        _ => '空位',
      };
      return CustomPainterSemantics(
        rect: Rect.fromCenter(
          center: grid.center(x, y),
          width: grid.step,
          height: grid.step,
        ),
        properties: SemanticsProperties(
          label: '${boardCoordinate(count, point)} $label',
          textDirection: TextDirection.ltr,
          button: onSelect != null,
          selected: point == selectedPoint ? true : null,
          onTap: onSelect == null ? null : () => onSelect!(point),
        ),
      );
    });
  };

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      grid.width != oldDelegate.grid.width ||
      position != oldDelegate.position ||
      lastPoint != oldDelegate.lastPoint ||
      selectedPoint != oldDelegate.selectedPoint;

  @override
  bool shouldRebuildSemantics(_BoardPainter oldDelegate) =>
      shouldRepaint(oldDelegate) ||
      (onSelect == null) != (oldDelegate.onSelect == null);
}
