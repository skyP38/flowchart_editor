import 'package:flutter/material.dart';

import 'diagram_scene.dart';

class SceneSvgRenderer {
  static String render(DiagramScene scene, {bool centerContent = false}) {
    final buf = StringBuffer();
    double offsetX = 0, offsetY = 0;
    Size canvas = scene.canvasSize;

    if (centerContent) {
      final bounds = _bounds(scene);
      if (bounds.width > 0 && bounds.height > 0) {
        const padding = 40.0;
        offsetX = padding - bounds.left;
        offsetY = padding - bounds.top;
        canvas = Size(bounds.width + padding * 2, bounds.height + padding * 2);
      }
    }

    buf.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buf.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'width="${canvas.width}" height="${canvas.height}">',
    );
    buf.writeln('<rect width="100%" height="100%" fill="white"/>');

    if (offsetX != 0 || offsetY != 0) {
      buf.writeln('<g transform="translate($offsetX, $offsetY)">');
    }

    // Сетка: сначала линии, потом подписи — чтобы текст был поверх.
    for (final l in scene.grid.lines) {
      buf.writeln(
        '<line x1="${l.from.dx}" y1="${l.from.dy}" '
        'x2="${l.to.dx}" y2="${l.to.dy}" '
        'stroke="#E5E7EB" stroke-width="1" />',
      );
    }
    for (final lab in scene.grid.labels) {
      final x = lab.isColumn ? lab.position.dx : lab.position.dx + 20;
      final y = lab.isColumn ? lab.position.dy + 18 : lab.position.dy;
      final anchor = lab.isColumn ? 'middle' : 'start';
      final baseline = lab.isColumn ? 'auto' : 'middle';
      buf.writeln(
        '<text x="$x" y="$y" text-anchor="$anchor" '
        'dominant-baseline="$baseline" '
        'font-family="Arial" font-size="18" fill="#666666">'
        '${_esc(lab.text)}</text>',
      );
    }

    // Связи
    for (final item in scene.connections) {
      final d = _pathToSvg(item.path);
      if (d.isEmpty) continue;
      buf.writeln(
        '<path d="$d" stroke="black" stroke-width="2" fill="none" />',
      );
      for (final a in item.arrows) {
        buf.writeln(_arrowSvg(a));
      }
    }

    // Узлы: контур + extras + текст
    for (final n in scene.nodes) {
      final outlineD = _pathToSvg(n.outline);
      buf.writeln(
        '<path d="$outlineD" stroke="black" stroke-width="2" fill="white" />',
      );
      for (final e in n.extras) {
        buf.writeln(
          '<path d="${_pathToSvg(e)}" stroke="black" stroke-width="2" '
          'fill="none" />',
        );
      }
      buf.writeln(
        '<text x="${n.textCenter.dx}" y="${n.textCenter.dy}" '
        'text-anchor="middle" dominant-baseline="middle" '
        'font-family="Arial" font-size="14" fill="black">'
        '${_esc(n.node.data.text)}</text>',
      );
    }

    if (offsetX != 0 || offsetY != 0) buf.writeln('</g>');
    buf.writeln('</svg>');
    return buf.toString();
  }

  static Rect _bounds(DiagramScene scene) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final n in scene.nodes) {
      final b = n.outline.getBounds();
      if (b.left < minX) minX = b.left;
      if (b.top < minY) minY = b.top;
      if (b.right > maxX) maxX = b.right;
      if (b.bottom > maxY) maxY = b.bottom;
    }
    for (final c in scene.connections) {
      if (c.path.computeMetrics().isEmpty) continue;
      final b = c.path.getBounds();
      if (b.left < minX) minX = b.left;
      if (b.top < minY) minY = b.top;
      if (b.right > maxX) maxX = b.right;
      if (b.bottom > maxY) maxY = b.bottom;
    }
    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static String _pathToSvg(Path path) {
    final parts = <String>[];
    for (final m in path.computeMetrics()) {
      for (double d = 0; d <= m.length; d += 1) {
        final t = m.getTangentForOffset(d);
        if (t == null) continue;
        final p = t.position;
        parts.add(d == 0 ? 'M ${p.dx} ${p.dy}' : 'L ${p.dx} ${p.dy}');
      }
    }
    return parts.join(' ');
  }

  static String _arrowSvg(ArrowItem a) {
    const len = 11.0;
    const half = 5.0;
    final ux = a.direction.dx;
    final uy = a.direction.dy;
    final baseX = a.tip.dx - ux * len;
    final baseY = a.tip.dy - uy * len;
    final px = -uy * half;
    final py = ux * half;
    return '<polygon points="${a.tip.dx},${a.tip.dy} '
        '${baseX + px},${baseY + py} ${baseX - px},${baseY - py}" '
        'fill="black" />';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
