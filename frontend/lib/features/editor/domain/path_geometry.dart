import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Один прямолинейный сегмент пути.
class PathSegment {
  final Offset start;
  final Offset end;
  const PathSegment(this.start, this.end);

  static const double _eps = 0.1;

  bool get isHorizontal =>
      (start.dy - end.dy).abs() < _eps && (start.dx - end.dx).abs() > _eps;

  bool get isVertical =>
      (start.dx - end.dx).abs() < _eps && (start.dy - end.dy).abs() > _eps;

  bool get isEmpty =>
      (start.dx - end.dx).abs() < _eps && (start.dy - end.dy).abs() < _eps;

  double get length => (end - start).distance;
  Offset get midpoint =>
      Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
}

/// Анализ `Path`: сэмплирование, разбиение на сегменты, поиск характерных точек.
///
/// Единая точка правды для всей геометрии путей. Раньше аналогичные
/// методы жили в [InsertionPointsService] (`_samplePath`, `_extractSegments`,
/// `_pathXAtY`, `_landingYAt`) с разными шагами сэмплирования (1.0 и 0.5),
/// из-за чего точки пересечения «прыгали» на пиксель.
class PathGeometry {
  const PathGeometry._();

  /// Шаг сэмплирования. Должен быть достаточно мелким, чтобы
  /// [xAtY]/[yAtX] находили пересечение с точностью < 1 px.
  static const double sampleStep = 0.5;

  // ─────────────────────────────── сэмплирование ───────────────────────────────

  static List<Offset> sample(Path path, {double step = sampleStep}) {
    final out = <Offset>[];
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d <= metric.length; d += step) {
        final t = metric.getTangentForOffset(d);
        if (t != null) out.add(t.position);
      }
    }
    return out;
  }

  // ─────────────────────────────── сегменты ───────────────────────────────

  /// Разбивает путь на максимальные прямолинейные сегменты.
  ///
  /// Склеивает соседние сэмплы одного направления. Толерантность 0.75
  /// гарантирует, что при `step = 0.5` соседние сэмплы на прямом участке
  /// (сдвиг 0.5 по одной оси) не «разрывают» сегмент.
  static List<PathSegment> segments(Path path) {
    final samples = sample(path);
    final segs = <PathSegment>[];
    if (samples.length < 2) return segs;

    const eps = 0.1;

    PathSegment? cur;
    for (int i = 0; i < samples.length; i++) {
      final b = samples[i];
      if (cur == null) {
        cur = PathSegment(b, b);
        continue;
      }
      final a = samples[i - 1];
      final abH = (a.dy - b.dy).abs() < eps && (a.dx - b.dx).abs() > eps;
      final abV = (a.dx - b.dx).abs() < eps && (a.dy - b.dy).abs() > eps;
      if ((cur.isHorizontal && abH) || (cur.isVertical && abV) || cur.isEmpty) {
        cur = PathSegment(cur.start, b);
      } else {
        if (!cur.isEmpty) segs.add(cur);
        cur = PathSegment(a, b);
      }
    }
    if (cur != null && !cur.isEmpty) segs.add(cur);
    return segs;
  }

  /// Самый длинный горизонтальный сегмент пути (или `null`).
  static PathSegment? longestHorizontal(Path path) {
    PathSegment? best;
    for (final s in segments(path)) {
      if (!s.isHorizontal) continue;
      if (best == null || s.length > best.length) best = s;
    }
    return best;
  }

  // ─────────────────────────────── точки ───────────────────────────────

  static Offset? midpoint(Path path) {
    for (final metric in path.computeMetrics()) {
      if (metric.length <= 0.1) continue;
      final t = metric.getTangentForOffset(metric.length / 2);
      if (t != null) return t.position;
    }
    return null;
  }

  /// Центр первого вертикального сегмента пути.
  ///
  /// Если заданы [obstacles], ищем **первое** (самое верхнее) пересечение
  /// этого вертикального сегмента с горизонтальными линиями препятствий.
  /// Если пересечение найдено — возвращаем середину между началом сегмента
  /// и пересечением; иначе — середину всего сегмента.
  ///
  /// Применяется для плюсов `yes`/`no`: если первая вертикаль далеко идёт
  /// до общей шины, а по ней на полпути проходит горизонталь другой связи,
  /// плюс ставится выше этой горизонтали — вне merge-зоны.
  static Offset? firstVerticalMidpoint(
    Path path, {
    List<Path> obstacles = const [],
  }) {
    PathSegment? firstVert;
    for (final s in segments(path)) {
      if (!s.isVertical) continue;
      firstVert = s;
      break;
    }
    if (firstVert == null) return null;

    final x = firstVert.start.dx;
    final topY = math.min(firstVert.start.dy, firstVert.end.dy);
    final bottomY = math.max(firstVert.start.dy, firstVert.end.dy);
    if (bottomY - topY < 0.5) return firstVert.midpoint;

    double? firstCrossingY;
    for (final obs in obstacles) {
      final y = _horizontalCrossingAtX(obs, x, topY, bottomY);
      if (y == null) continue;
      if (firstCrossingY == null || y < firstCrossingY) {
        firstCrossingY = y;
      }
    }

    final midBottom = firstCrossingY ?? bottomY;
    return Offset(x, (topY + midBottom) / 2);
  }

  /// Минимальный Y ∈ (topY, bottomY), где [obstacle] проходит горизонтально
  /// через X = [x]. Только строго внутренние пересечения — касание концов
  /// (верх/низ вертикали) не считается, иначе будем «цепляться» за порт.
  static double? _horizontalCrossingAtX(
    Path obstacle,
    double x,
    double topY,
    double bottomY,
  ) {
    double? best;
    for (final s in segments(obstacle)) {
      if (!s.isHorizontal) continue;
      final y = s.start.dy; // == s.end.dy для горизонтали
      if (y <= topY + 0.5 || y >= bottomY - 0.5) continue;
      final xLo = math.min(s.start.dx, s.end.dx);
      final xHi = math.max(s.start.dx, s.end.dx);
      if (x < xLo - 0.5 || x > xHi + 0.5) continue;
      if (best == null || y < best) best = y;
    }
    return best;
  }

  // /// Центр первого вертикального сегмента пути.
  // static Offset? firstVerticalMidpoint(Path path) {
  //   for (final s in segments(path)) {
  //     if (!s.isVertical) continue;
  //     return s.midpoint;
  //   }
  //   return null;
  // }

  // ─────────────────────────────── пересечения ───────────────────────────────

  /// X пути в заданном Y (или `null`, если Y не на пути).
  static double? xAtY(Path path, double targetY, {double eps = 0.75}) {
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d <= metric.length; d += sampleStep) {
        final t = metric.getTangentForOffset(d);
        if (t == null) continue;
        if ((t.position.dy - targetY).abs() < eps) return t.position.dx;
      }
    }
    return null;
  }

  /// Y пути в заданном X (или `null`, если X не на пути).
  static double? yAtX(Path path, double targetX, {double eps = 0.75}) {
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d <= metric.length; d += sampleStep) {
        final t = metric.getTangentForOffset(d);
        if (t == null) continue;
        if ((t.position.dx - targetX).abs() < eps) return t.position.dy;
      }
    }
    return null;
  }

  /// Y, где путь приземляется на общую вертикаль [centerX] перед [targetTop].
  ///
  /// Ищет самый нижний сэмпл с `x ≈ centerX` и `y < targetTop` — это
  /// точка, где горизонталь ветки упирается в вертикаль target'а.
  static double? landingYAt(Path path, double centerX, double targetTop) {
    final samples = sample(path);
    double? best;
    for (final p in samples) {
      if ((p.dx - centerX).abs() > 1.0) continue;
      if (p.dy >= targetTop - 1.0) continue;
      if (best == null || p.dy < best) best = p.dy;
    }
    return best;
  }
}
