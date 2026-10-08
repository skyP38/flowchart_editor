import 'package:flutter/material.dart';

// Преобразует номер колонки(цифру) в букву
String numberToLetter(int n) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  String result = '';
  while (n >= 0) {
    result = alphabet[n % 26] + result;
    n = (n / 26).floor() - 1;
    if (n < 0) break;
  }
  return result;
}

// Рисует подписи сетки: цифры сверху(столбцы), буквы слева (строки)
// Нумерация привязана к расположению блока Start
class GridLabelsPainter extends CustomPainter {
  final double? stepX;
  final double? stepY;
  final Offset startPosition;

  GridLabelsPainter({
    required this.stepX,
    required this.stepY,
    required this.startPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (stepX == null || stepY == null) return;

    final textStyle = TextStyle(
      color: Colors.grey.shade700,
      fontSize: 18,
      fontWeight: FontWeight.w500,
    );

    // Подписи столбцов (цифры) сверху
    int firstCol = ((startPosition.dx) / stepX!).floor();
    int lastCol = ((size.width - startPosition.dx) / stepX!).ceil();
    for (int col = firstCol; col <= lastCol; col++) {
      final double stepXgrid = stepX! + 70;
      final double startCenterX = startPosition.dx - 10 + stepX! / 2;
      // double x = (col + 1) * stepX!;
      double x = startCenterX + col * stepXgrid;
      if (x < 0 || x > size.width) continue;
      final number = col + 1;
      final textSpan = TextSpan(text: '$number', style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x, 2));
    }

    // Подписи строк (буквы) слева
    final double stepYgrid = stepY! + 40.0;
    final double startCenterY = startPosition.dy + stepY! / 2;
    int firstRow = ((0 - startCenterY) / stepY!).floor();
    int lastRow = ((size.height - startCenterY) / stepY!).ceil();
    for (int row = firstRow; row <= lastRow; row++) {
      // double y = startPosition.dy + row * stepY! + stepY! / 2;
      // double y = (row * 1.5) * stepY!;
      double y = startCenterY + row * stepYgrid;
      if (y < 0 || y > size.height) continue;
      String letter = numberToLetter(row);
      final textSpan = TextSpan(text: letter, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      // textPainter.paint(canvas, Offset(2, y));
      textPainter.paint(canvas, Offset(2, y - textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant GridLabelsPainter oldDelegate) {
    return oldDelegate.stepX != stepX ||
        oldDelegate.stepY != stepY ||
        oldDelegate.startPosition != startPosition;
  }
}
