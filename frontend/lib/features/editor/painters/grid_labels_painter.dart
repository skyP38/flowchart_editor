import 'package:flowchart_editor_frontend/features/editor/constants/diagram_constants.dart';
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
  final double columnWidth; // = spacing.stepX
  final double rowHeight; // = spacing.stepY
  final double nodeWidth; // = nodeSize.width
  final double nodeHeight; // = nodeSize.height
  // final double? stepX;
  // final double? stepY;
  final Offset startPosition;

  GridLabelsPainter({
    required this.columnWidth,
    required this.rowHeight,
    required this.nodeWidth,
    required this.nodeHeight,
    // required this.stepX,
    // required this.stepY,
    required this.startPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // if (stepX == null || stepY == null) return;

    final textStyle = TextStyle(
      color: Colors.grey.shade700,
      fontSize: GridConstants.fontSize,
      fontWeight: FontWeight.w500,
    );

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

      // Цифра по центру ячейки
      final labelX = x + columnWidth / 2;
      if (labelX >= 0 && labelX <= size.width) {
        final number = col + 1;
        final tp = TextPainter(
          text: TextSpan(text: '$number', style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 2));
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

      final labelY = y + rowHeight / 2;
      if (labelY >= 0 && labelY <= size.height) {
        final letter = numberToLetter(row);
        final tp = TextPainter(
          text: TextSpan(text: letter, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(2, y - tp.height / 2));
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
