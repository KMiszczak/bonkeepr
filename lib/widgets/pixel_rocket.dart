import 'package:flutter/material.dart';

/// Small, crisp 8-bit red rocket with a black pixel outline.
class PixelRocket extends StatelessWidget {
  const PixelRocket({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _PixelRocketPainter());
}

class _PixelRocketPainter extends CustomPainter {
  static const _pixels = [
    '.....#.....',
    '....###....',
    '...#RRR#...',
    '..#RRRRR#..',
    '.#RRRRRRR#.',
    '#RRRRRRRRR#',
    '#RR#RRR#RR#',
    '.#R#RRR#R#.',
    '..#RRRRR#..',
    '...#R#R#...',
    '....#Y#....',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / _pixels.first.length;
    final cellHeight = size.height / _pixels.length;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < _pixels.length; y++) {
      for (var x = 0; x < _pixels[y].length; x++) {
        final color = switch (_pixels[y][x]) {
          '#' => Colors.black,
          'R' => const Color(0xFFE31B23),
          'Y' => const Color(0xFFFFD700),
          _ => null,
        };
        if (color == null) continue;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(x * cellWidth, y * cellHeight, cellWidth, cellHeight),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelRocketPainter oldDelegate) => false;
}
