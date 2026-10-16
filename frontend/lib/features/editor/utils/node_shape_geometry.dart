import 'package:flutter/material.dart';
import '../models/flow_models.dart';

// Геометрия фигур блоков
class NodeShapeGeometry {
  NodeShapeGeometry._();

  // Главный контур фигуры (по нему рисуется обводка и заливка)
  static Path outline(Size size, GostNodeData data) {
    switch (data) {
      case TerminalBlock():
        // терминал
        return Path()..addRRect(
          RRect.fromRectAndRadius(
            Offset.zero & size,
            const Radius.circular(40),
          ),
        );
      case ProcessBlock():
        // Обычный прямоугольник
        return Path()..addRect(Offset.zero & size);
      case LogicBlock():
        return _diamond(size);
      case IOBlock():
        return _parallelogram(size, skew: 20);
      case SubroutineBlock():
        // Внешний контур - прямоугольник; боковые линии идут в extras()
        return Path()..addRect(Offset.zero & size);
      case ForBlock():
        return _hexagon(size);
    }
  }

  // Дополнительные линии поверх контура для подпрограммы
  static List<Path> extras(Size size, GostNodeData data) {
    if (data is SubroutineBlock) {
      final w = size.width;
      final h = size.height;
      return [
        Path()
          ..moveTo(10, 0)
          ..lineTo(10, h),
        Path()
          ..moveTo(w - 10, 0)
          ..lineTo(w - 10, h),
      ];
    }
    return const [];
  }

  // примитивы

  static Path _diamond(Size s) => Path()
    ..moveTo(s.width / 2, 0)
    ..lineTo(s.width, s.height / 2)
    ..lineTo(s.width / 2, s.height)
    ..lineTo(0, s.height / 2)
    ..close();

  static Path _parallelogram(Size s, {required double skew}) => Path()
    ..moveTo(skew, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width - skew, s.height)
    ..lineTo(0, s.height)
    ..close();

  static Path _hexagon(Size s) {
    final w = s.width;
    final h = s.height;
    final h2 = h / 2;
    final w4 = w / 4;
    return Path()
      ..moveTo(w4, 0)
      ..lineTo(w * 3 / 4, 0)
      ..lineTo(w, h2)
      ..lineTo(w * 3 / 4, h)
      ..lineTo(w4, h)
      ..lineTo(0, h2)
      ..close();
  }
}
