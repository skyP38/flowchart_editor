import 'package:flowchart_editor_frontend/features/editor/constants/diagram_constants.dart';
import 'package:flutter/material.dart';

// Рисует полупрозрачный прямоугольник выделения
// Используется во время drag пока пользователь тянет рамку объекта
class SelectionRectPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  SelectionRectPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: SelectionConstants.fillOpacity)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = SelectionConstants.borderWidth;
    canvas.drawRect(rect, paint);
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant SelectionRectPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}
