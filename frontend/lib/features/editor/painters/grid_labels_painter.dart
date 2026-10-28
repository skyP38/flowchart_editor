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
  final double columnWidth;
  final double rowHeight;
  final double nodeWidth;
  final double nodeHeight;
  final Offset startPosition;

  GridLabelsPainter({
    required this.columnWidth,
    required this.rowHeight,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.startPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Стиль для линий сетки
    final linePaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1.0;

    // Находим левую/верхнюю границу ячейки
    final shiftX = (columnWidth - nodeWidth) / 2;
    final shiftY = (rowHeight - nodeHeight) / 2;
    final startBoundaryX = startPosition.dx - shiftX;
    final startBoundaryY = startPosition.dy - shiftY;

    int firstCol = (-startBoundaryX / columnWidth).floor();
    int lastCol = ((size.width - startBoundaryX) / columnWidth).ceil();
    //  вертикальные линии
    for (int col = firstCol; col <= lastCol; col++) {
      // Линия сетки на границе
      final x = startBoundaryX + col * columnWidth;
      if (x >= 0 && x <= size.width) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      }
    }

    // Строки: аналогично, центр строки 0 = центр Start-блока.
    int firstRow = (-startBoundaryY / rowHeight).floor();
    int lastRow = ((size.height - startBoundaryY) / rowHeight).ceil();
    // горизонтальные линии
    for (int row = firstRow; row <= lastRow; row++) {
      final y = startBoundaryY + row * rowHeight;
      if (y >= 0 && y <= size.height) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant GridLabelsPainter old) =>
      old.columnWidth != columnWidth ||
      old.rowHeight != rowHeight ||
      old.nodeWidth != nodeWidth ||
      old.nodeHeight != nodeHeight ||
      old.startPosition != startPosition;
}
