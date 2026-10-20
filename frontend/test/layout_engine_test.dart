import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowchart_editor_frontend/features/editor/domain/layout_engine.dart';
import 'package:flowchart_editor_frontend/features/editor/domain/flowchart_graph.dart';
import 'package:flowchart_editor_frontend/features/editor/factories/node_factory.dart';
import 'package:flowchart_editor_frontend/features/editor/models/flow_models.dart';
import 'package:flowchart_editor_frontend/features/editor/models/editor_models.dart';

void main() {
  group('LayoutEngine basic layout', () {
    test('Start -> Process -> End', () {
      // Start -> Process -> End
      final start = NodeFactory.createNode(
        id: 'id_start1',
        data: const TerminalBlock('Start'),
        position: Offset.zero,
      );
      final process = NodeFactory.createNode(
        id: 'id_proc11',
        data: const ProcessBlock('Smth'),
        position: Offset.zero,
      );
      final end = NodeFactory.createNode(
        id: 'id_end111',
        data: const TerminalBlock('End'),
        position: Offset.zero,
      );

      final graph = FlowchartGraph(
        nodes: {start.name: start, process.name: process, end.name: end},
        connections: [
          ConnectionData(
            id: 'c1',
            sourceNodeName: start.name,
            sourcePort: 'out',
            targetNodeName: process.name,
            targetPort: 'in',
          ),
          ConnectionData(
            id: 'c2',
            sourceNodeName: process.name,
            sourcePort: 'out',
            targetNodeName: end.name,
            targetPort: 'in',
          ),
        ],
      );

      final engine = LayoutEngine(
        nodeSize: const Size(160, 80),
        spacing: const LayoutSpacing(stepX: 230, stepY: 120),
      );

      final positions = engine.compute(graph);

      // Rank (Y) check
      expect(positions[start.name]!.dy, positions[process.name]!.dy - 120);
      expect(positions[process.name]!.dy, positions[end.name]!.dy - 120);

      // Column (X) check: все на колонке 0
      expect(positions[start.name]!.dx, positions[process.name]!.dx);
      expect(positions[process.name]!.dx, positions[end.name]!.dx);
    });

    test('Logic block', () {
      // Start -> Logic
      // Logic -> (yes) Process1 -> End
      // Logic -> (no)  Process2 -> End
      final start = NodeFactory.createNode(
        id: '1id_start1',
        data: const TerminalBlock('Start'),
        position: Offset.zero,
      );
      final logic = NodeFactory.createNode(
        id: 'id_logic1',
        data: const LogicBlock('Check'),
        position: Offset.zero,
      );
      final pYes = NodeFactory.createNode(
        id: 'id_yes111',
        data: const ProcessBlock('Yes'),
        position: Offset.zero,
      );
      final pNo = NodeFactory.createNode(
        id: 'id_no1111',
        data: const ProcessBlock('No'),
        position: Offset.zero,
      );
      final end = NodeFactory.createNode(
        id: 'id_end111',
        data: const TerminalBlock('End'),
        position: Offset.zero,
      );

      final graph = FlowchartGraph(
        nodes: {
          start.name: start,
          logic.name: logic,
          pYes.name: pYes,
          pNo.name: pNo,
          end.name: end,
        },
        connections: [
          ConnectionData(
            id: 'c1',
            sourceNodeName: start.name,
            sourcePort: 'out',
            targetNodeName: logic.name,
            targetPort: 'in',
          ),
          ConnectionData(
            id: 'c2',
            sourceNodeName: logic.name,
            sourcePort: 'yes',
            targetNodeName: pYes.name,
            targetPort: 'in',
          ),
          ConnectionData(
            id: 'c3',
            sourceNodeName: logic.name,
            sourcePort: 'no',
            targetNodeName: pNo.name,
            targetPort: 'in',
          ),
          ConnectionData(
            id: 'c4',
            sourceNodeName: pYes.name,
            sourcePort: 'out',
            targetNodeName: end.name,
            targetPort: 'in',
          ),
          ConnectionData(
            id: 'c5',
            sourceNodeName: pNo.name,
            sourcePort: 'out',
            targetNodeName: end.name,
            targetPort: 'in',
          ),
        ],
      );

      final engine = LayoutEngine(
        nodeSize: const Size(160, 80),
        spacing: const LayoutSpacing(stepX: 230, stepY: 120),
      );

      final positions = engine.compute(graph);

      // Main line (Start, Logic, pYes) stays on col 0
      expect(positions[start.name]!.dx, positions[logic.name]!.dx);
      expect(positions[logic.name]!.dx, positions[pYes.name]!.dx);

      // No branch shifts to col 1 (dx > main)
      expect(positions[pNo.name]!.dx, greaterThan(positions[logic.name]!.dx));

      // End returns to col 0
      expect(positions[end.name]!.dx, positions[start.name]!.dx);
    });
  });
}
