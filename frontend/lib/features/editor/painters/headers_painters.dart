import 'package:flowchart_editor_frontend/features/editor/constants/diagram_constants.dart';
import 'package:flutter/material.dart';

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

/// Подписи столбцов (цифры сверху)
class ColumnHeadersPainter extends CustomPainter {
  final double scrollOffset;
  final double columnWidth;
  final double nodeWidth;
  final double startPositionX;
  final double scale;
  final TextStyle textStyle;

  ColumnHeadersPainter({
    required this.scrollOffset,
    required this.columnWidth,
    required this.nodeWidth,
    required this.startPositionX,
    required this.scale,
    required this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (columnWidth <= 0) return;

    final shiftX = (columnWidth - nodeWidth) / 2;
    final startBoundaryCanvas = startPositionX - shiftX;
    final screenStart = startBoundaryCanvas * scale - scrollOffset;
    final cellW = columnWidth * scale;

    final first = ((-screenStart) / cellW).floor();
    final last = ((size.width - screenStart) / cellW).ceil();

    for (int col = first; col <= last; col++) {
      final left = screenStart + col * cellW;
      final centerX = left + cellW / 2;
      if (centerX < -20 || centerX > size.width + 20) continue;
      final number = col + 1;
      final tp = TextPainter(
        text: TextSpan(text: '$number', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(centerX - tp.width / 2, (size.height - tp.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ColumnHeadersPainter old) =>
      old.scrollOffset != scrollOffset ||
      old.columnWidth != columnWidth ||
      old.nodeWidth != nodeWidth ||
      old.startPositionX != startPositionX ||
      old.scale != scale ||
      old.textStyle != textStyle;
}

/// Подписи строк (буквы слева)
class RowHeadersPainter extends CustomPainter {
  final double scrollOffset;
  final double rowHeight;
  final double nodeHeight;
  final double startPositionY;
  final double scale;
  final TextStyle textStyle;

  RowHeadersPainter({
    required this.scrollOffset,
    required this.rowHeight,
    required this.nodeHeight,
    required this.startPositionY,
    required this.scale,
    required this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rowHeight <= 0) return;

    final shiftY = (rowHeight - nodeHeight) / 2;
    final startBoundaryCanvas = startPositionY - shiftY;
    final screenStart = startBoundaryCanvas * scale - scrollOffset;
    final cellH = rowHeight * scale;

    final first = ((-screenStart) / cellH).floor();
    final last = ((size.height - screenStart) / cellH).ceil();

    for (int row = first; row <= last; row++) {
      final top = screenStart + row * cellH;
      final centerY = top + cellH / 2;
      if (centerY < -20 || centerY > size.height + 20) continue;
      final letter = numberToLetter(row);
      final tp = TextPainter(
        text: TextSpan(text: letter, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(GridConstants.labelLeftX, centerY - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant RowHeadersPainter old) =>
      old.scrollOffset != scrollOffset ||
      old.rowHeight != rowHeight ||
      old.nodeHeight != nodeHeight ||
      old.startPositionY != startPositionY ||
      old.scale != scale ||
      old.textStyle != textStyle;
}
