import 'package:flutter/material.dart';

/// Bold red pixel X with a black outline and no surrounding frame.
class PixelClearIcon extends StatelessWidget {
  const PixelClearIcon({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _PixelXPainter());
}

class _PixelXPainter extends CustomPainter {
  static const _gridSize = 11;
  static const _red = Color(0xFFFF0033);

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / _gridSize;
    final cellHeight = size.height / _gridSize;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < _gridSize; y++) {
      for (var x = 0; x < _gridSize; x++) {
        final firstDiagonal = (x - y).abs();
        final secondDiagonal = (x - (_gridSize - 1 - y)).abs();
        final distance = firstDiagonal < secondDiagonal
            ? firstDiagonal
            : secondDiagonal;
        if (distance > 2) continue;
        paint.color = distance <= 1 ? _red : Colors.black;
        canvas.drawRect(
          Rect.fromLTWH(x * cellWidth, y * cellHeight, cellWidth, cellHeight),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelXPainter oldDelegate) => false;
}
