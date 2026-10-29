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

  final bool showLines;
  final bool showLabels;

  GridLabelsPainter({
    required this.columnWidth,
    required this.rowHeight,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.startPosition,
    this.showLines = true,
    this.showLabels = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Стиль для линий сетки
    final linePaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1.0;

    final textStyle = TextStyle(
      color: Colors.grey.shade700,
      fontSize: 18,
      fontWeight: FontWeight.w500,
    );

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

      if (showLabels) {
        final labelX = x + columnWidth / 2;
        if (labelX >= 0 && labelX <= size.width) {
          final tp = TextPainter(
            text: TextSpan(text: '${col + 1}', style: textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(labelX - tp.width / 2, 4));
        }
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

      if (showLabels) {
        final labelY = y + rowHeight / 2;
        if (labelY >= 0 && labelY <= size.height) {
          final tp = TextPainter(
            text: TextSpan(text: numberToLetter(row), style: textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(4, labelY - tp.height / 2));
        }
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
