import 'package:flowchart_editor_frontend/features/editor/domain/layout_engine.dart';
import 'package:flutter/material.dart';

import '../domain/connection_router.dart';
import '../domain/flowchart_graph.dart';
import '../utils/scene_builder.dart';
import '../utils/svg_renderer.dart';

class SvgExporter {
  SvgExporter._();

  static String export({
    required FlowchartGraph graph,
    required ConnectionRouter router,
    required Size nodeSize,
    required LayoutSpacing spacing,
    required Size canvasSize,
    required bool showGrid,
    bool centerContent = false,
    bool showLabels = true,
  }) {
    final scene =
        SceneBuilder(
          router: router,
          nodeSize: nodeSize,
          spacing: spacing,
        ).build(
          graph: graph,
          canvasSize: canvasSize,
          showGrid: showGrid,
          showLabels: showLabels,
        );
    return SceneSvgRenderer.render(scene, centerContent: centerContent);
  }
}
