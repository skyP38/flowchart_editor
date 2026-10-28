import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/scheduler.dart';
import 'package:flutter/gestures.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import '../factories/node_factory.dart';
import '../state/flow_controller.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../models/flow_models.dart';
import '../widgets/gost_node_builder.dart';
import '../widgets/vertical_toolbar.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import '../models/editor_models.dart';
import '../painters/connection_painter.dart';
import '../painters/selection_painter.dart';
import '../painters/grid_labels_painter.dart';
import '../domain/layout_engine.dart';

import '../persistence/editor_state.dart';
import '../domain/connection_router.dart';
import '../domain/insertion_points.dart';
import '../constants/diagram_constants.dart';
import '../utils/svg_exporter.dart';
import '../../../core/storage/guest_diagram_storage.dart';
import '../painters/headers_painters.dart';
import '../domain/flowchart_graph.dart';

// Главный экран редактора блок-схем
class EditorScreen extends StatefulWidget {
  final EditorSnapshot? initialSnapshot;
  final Future<void> Function(EditorSnapshot snapshot, String previewSvg)?
  onSave;

  final bool canSave;
  final VoidCallback? onBack;

  const EditorScreen({
    super.key,
    this.initialSnapshot,
    this.onSave,
    this.canSave = true,
    this.onBack,
  });
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with TickerProviderStateMixin {
  final FlowController _controller = FlowController();

  Set<String> _selectedNodeNames = {};
  Offset? _selectionStart;
  Offset? _selectionEnd;
  bool _isSelecting = false;
  bool _isSelectingFromEmpty = false;
  List<InsertionPoint> _insertionPoints = [];
  GostNodeData? _selectedPrototype;
  String? _selectedConnectionId;

  final FocusNode _focusNode = FocusNode();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  static const double _minScale = ScaleConstants.minScale;
  static const double _maxScale = ScaleConstants.maxScale;

  late ConnectionRouter _router;
  late InsertionPointsService _insertionPointsService;

  Timer? _saveDebounce;
  bool _autoSaveEnabled = false;

  String? _hoveredConnectionId;
  InsertionPoint? _hoveredPoint;

  late final Ticker _zoomTicker;
  double _zoomTarget = 1.0;
  bool _zoomTickerRunning = false;
  Offset _zoomAnchorScreen = Offset.zero;
  Offset _zoomAnchorContent = Offset.zero;

  @override
  void initState() {
    super.initState();
    _zoomTicker = createTicker(_onZoomTick);
    _zoomTarget = _controller.scale;
    if (widget.initialSnapshot != null) {
      _controller.fromSnapshot(widget.initialSnapshot!);
      _controller.clearHistory();
    } else {
      _controller.initDefaultDiagram();
    }
    _rebuildRouter();
    _insertionPoints = _insertionPointsService.compute(_controller.graph);
    _controller.addListener(_onControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _focusNode.requestFocus();

      // Гостевой режим - восстанавливаем черновик
      if (!widget.canSave && widget.onSave == null) {
        await _tryRestoreGuestDraft();
        if (!mounted) return;
        _autoSaveEnabled = true;
      }
    });

    debugPrint(
      '[EditorScreen] init snapshot=${widget.initialSnapshot != null}',
    );
    if (widget.initialSnapshot != null) {
      _controller.fromSnapshot(widget.initialSnapshot!);
      debugPrint(
        '[EditorScreen] fromSnapshot done, '
        'nodes=${_controller.nodes.length}',
      );
      _controller.clearHistory();
    } else {
      _controller.initDefaultDiagram();
      debugPrint(
        '[EditorScreen] default done, '
        'nodes=${_controller.nodes.length}',
      );
    }
  }

  void _handleCanvasHover(Offset? localPos) {
    if (localPos == null) {
      if (_hoveredConnectionId != null || _hoveredPoint != null) {
        setState(() {
          _hoveredConnectionId = null;
          _hoveredPoint = null;
        });
      }
      return;
    }

    InsertionPoint? best;
    double bestDist = 20.0;
    for (final p in _insertionPoints) {
      final d = (localPos - p.position).distance;
      if (d < bestDist) {
        bestDist = d;
        best = p;
      }
    }

    final newId = best?.connection.id;
    if (newId != _hoveredConnectionId || !identical(best, _hoveredPoint)) {
      setState(() {
        _hoveredConnectionId = newId;
        _hoveredPoint = best;
      });
    }
  }

  Future<void> _tryRestoreGuestDraft() async {
    final raw = await GuestDiagramStorage.instance.load();
    if (raw == null || !mounted) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final snapshot = EditorSnapshot.fromJson(json);
      _controller.fromSnapshot(snapshot);
      _controller.clearHistory();
      setState(() {
        _insertionPoints = _insertionPointsService.compute(_controller.graph);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Восстановлен черновик')));
    } catch (e) {
      debugPrint('[GuestEditor] restore failed: $e');
      await GuestDiagramStorage.instance.clear();
    }
  }

  void _scheduleAutoSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _flushAutoSave);
  }

  Future<void> _flushAutoSave() async {
    if (!_autoSaveEnabled || !mounted) return;
    try {
      final snap = _controller.toSnapshot();
      await GuestDiagramStorage.instance.save(jsonEncode(snap.toJson()));
    } catch (e) {
      debugPrint('[GuestEditor] autosave failed: $e');
    }
  }

  // Пересобирает роутер и сервис точек вставки под текущий размер блока
  void _rebuildRouter() {
    _router = ConnectionRouter(
      nodeSize: _controller.nodeSize,
      spacing: _controller.spacing,
    );
    _insertionPointsService = InsertionPointsService(router: _router);
  }

  FlowchartGraph? _lastGraph;
  Size? _lastRouterNodeSize;
  double? _lastStepX, _lastStepY;

  void _onControllerChanged() {
    if (!mounted) return;

    final spacing = _controller.spacing;
    final nodeSize = _controller.nodeSize;

    final graphChanged = !identical(_controller.graph, _lastGraph);
    final sizeChanged =
        nodeSize != _lastRouterNodeSize ||
        spacing.stepX != _lastStepX ||
        spacing.stepY != _lastStepY;

    if (sizeChanged) {
      _rebuildRouter();
      _lastRouterNodeSize = nodeSize;
      _lastStepX = spacing.stepX;
      _lastStepY = spacing.stepY;
    }

    if (graphChanged || sizeChanged) {
      _lastGraph = _controller.graph;
      setState(() {
        _insertionPoints = _insertionPointsService.compute(_controller.graph);
      });
    } else {
      // только scale / grid / toolbar — граф не менялся
      setState(() {});
    }

    if (_autoSaveEnabled) _scheduleAutoSave();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _zoomTicker.dispose();
    super.dispose();
  }

  void _handleZoomSignal(PointerSignalEvent event) {
    final hw = HardwareKeyboard.instance;
    final ctrl = hw.isControlPressed || hw.isMetaPressed;

    double? newTarget;
    if (event is PointerScrollEvent) {
      if (!ctrl) return;
      final delta = event.scrollDelta.dy;
      if (delta == 0) return;
      newTarget = (_zoomTarget - delta * 0.001).clamp(_minScale, _maxScale);
    } else if (event is PointerScaleEvent) {
      if ((event.scale - 1.0).abs() < 1e-4) return;
      newTarget = (_zoomTarget * event.scale).clamp(_minScale, _maxScale);
    } else {
      return;
    }

    if ((newTarget - _zoomTarget).abs() < 1e-5) return;

    final scrollX = _safeOffset(_verticalScrollController);
    final scrollY = _safeOffset(_horizontalScrollController);

    final lp = event.localPosition;
    final scale = _controller.scale;

    final anchorContent = Offset(lp.dx / scale, lp.dy / scale);
    final anchorScreen = Offset(lp.dx - scrollX, lp.dy - scrollY);
    final target = newTarget;

    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _zoomAnchorContent = anchorContent;
      _zoomAnchorScreen = anchorScreen;
      _zoomTarget = target;
      if (!_zoomTickerRunning) {
        _zoomTicker.start();
        _zoomTickerRunning = true;
      }
    });
  }

  void _onZoomTick(Duration _) {
    final oldScale = _controller.scale;
    final diff = _zoomTarget - oldScale;

    if (diff.abs() < 0.0008) {
      _controller.setScale(_zoomTarget);
      _applyZoomScroll(oldScale, _zoomTarget);
      _zoomTicker.stop();
      _zoomTickerRunning = false;
      return;
    }

    // сглаживание; 0.3 ≈ ~5 кадров до цели
    final next = oldScale + diff * 0.3;
    _controller.setScale(next);
    _applyZoomScroll(oldScale, next); // синхронно
  }

  void _applyZoomScroll(double oldScale, double newScale) {
    for (final pos in _verticalScrollController.positions) {
      if (!pos.hasContentDimensions || !pos.hasViewportDimension) continue;
      final oldContentW = pos.maxScrollExtent + pos.viewportDimension;
      final newMaxScroll =
          oldContentW * (newScale / oldScale) - pos.viewportDimension;
      final targetPx = _zoomAnchorContent.dx * newScale - _zoomAnchorScreen.dx;
      final clamped = targetPx
          .clamp(0.0, math.max(0.0, newMaxScroll))
          .toDouble();
      if (pos.hasPixels) pos.jumpTo(clamped);
    }

    for (final pos in _horizontalScrollController.positions) {
      if (!pos.hasContentDimensions || !pos.hasViewportDimension) continue;
      final oldContentH = pos.maxScrollExtent + pos.viewportDimension;
      final newMaxScroll =
          oldContentH * (newScale / oldScale) - pos.viewportDimension;
      final targetPx = _zoomAnchorContent.dy * newScale - _zoomAnchorScreen.dy;
      final clamped = targetPx
          .clamp(0.0, math.max(0.0, newMaxScroll))
          .toDouble();
      if (pos.hasPixels) pos.jumpTo(clamped);
    }
  }

  // Вычисляет размер области холста с учётом всех блоков и padding
  Size _getContentSize() {
    final nodes = _controller.nodes;
    final nodeSize = _controller.nodeSize;
    if (nodes.isEmpty) return const Size(1500, 1000);
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final data in nodes.values) {
      final pos = data.position;
      minX = minX < pos.dx ? minX : pos.dx;
      minY = minY < pos.dy ? minY : pos.dy;
      maxX = maxX > pos.dx + nodeSize.width ? maxX : pos.dx + nodeSize.width;
      maxY = maxY > pos.dy + nodeSize.height ? maxY : pos.dy + nodeSize.height;
    }
    const padding = 400.0;
    double width = maxX - minX + padding;
    double height = maxY - minY + padding;
    // Минимальные размеры, чтобы полосы прокрутки точно появились
    width = width < 1200 ? 1200 : width;
    height = height < 800 ? 800 : height;

    return Size(width, height);
  }

  /// Безопасно читает offset у ScrollController, даже если к нему
  /// прицеплено 0 или 2+ позиций (транзиентные состояния при rebuild).
  double _safeOffset(ScrollController controller) {
    final positions = controller.positions;
    if (positions.isEmpty) return 0;
    final pos = positions.first;
    if (!pos.hasContentDimensions || !pos.hasPixels) return 0;
    return pos.pixels;
  }

  // Проверяет, попадает ли точка в прямоугольник какого-либо узла
  bool _isPointOverAnyNode(Offset point) {
    final nodes = _controller.nodes;
    final nodeSize = _controller.nodeSize;
    for (final data in nodes.values) {
      final pos = data.position;
      final rect = Rect.fromLTWH(
        pos.dx,
        pos.dy,
        nodeSize.width,
        nodeSize.height,
      );
      if (rect.contains(point)) return true;
    }
    return false;
  }

  // Обработка удаления блока
  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // Ctrl+Z (отмена)
    if (event.logicalKey == LogicalKeyboardKey.keyZ &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _controller.undo();
      return;
    }
    // Ctrl+Y или Ctrl+Shift+Z (повтор)
    if (event.logicalKey == LogicalKeyboardKey.keyZ &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        HardwareKeyboard.instance.isShiftPressed) {
      _controller.redo();
      return;
    }
    // Ctrl+Y (альтернатива)
    if (event.logicalKey == LogicalKeyboardKey.keyY &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      _controller.redo();
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteSelection();
    }
  }

  void _deleteSelection() {
    if (_selectedNodeNames.isNotEmpty) {
      final toDelete = List.of(_selectedNodeNames);
      for (final nodeName in toDelete) {
        final node = _controller.nodes[nodeName];
        final isProtected =
            node?.data is TerminalBlock &&
            (node!.data.text == 'Start' || node.data.text == 'End');
        if (!isProtected) {
          _controller.removeNode(nodeName);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нельзя удалить блок Start или End')),
          );
        }
      }
      setState(() {
        _selectedNodeNames.clear();
      });
    } else if (_selectedConnectionId != null) {
      _controller.removeConnection(_selectedConnectionId!);
      setState(() => _selectedConnectionId = null);
    }
  }

  // Обрабатывает тап по холсту:
  //  - точка вставки -> вставить новый блок (если выбран прототип);
  //  - связь -> выделить ее;
  //  - пустое место -> сбросить выделение.
  void _handleCanvasTapDown(TapDownDetails details) {
    final localPos = details.localPosition;

    // Проверка точки вставки
    InsertionPoint? point;
    double bestDist = 12.0;
    for (final pnt in _insertionPoints) {
      final d = (localPos - pnt.position).distance;
      if (d < bestDist) {
        bestDist = d;
        point = pnt;
      }
    }
    if (point != null) {
      debugPrint(
        '[tap+] pos=${point.position} '
        'afterMerge=${point.isAfterMerge} '
        'connId=${point.connection.id}',
      );
      if (_selectedPrototype != null) {
        if (point.isAfterMerge) {
          _controller.insertAfterLogicMerge(
            point.connection.id!,
            point.mergeOtherConnIds,
            _selectedPrototype!,
          );
        } else {
          _controller.insertNodeOnConnection(
            point.connection.id!,
            _selectedPrototype!,
          );
        }
        setState(() => _selectedPrototype = null);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выберите тип блока на панели слева')),
        );
      }
      _isSelectingFromEmpty = false;
      return;
    }
    ConnectionData? tappedConnection;
    double minDistance = 15.0;

    final graph = _controller.graph;
    // final nodes = _controller.nodes;
    final connections = _controller.connections;
    // final nodeSize = _controller.nodeSize;

    for (final conn in connections) {
      final path = _router.build(conn, graph);
      // Разбиение пути на сегменты и поиск минимальное расстояние
      double minDistForConn = double.infinity;
      final metrics = path.computeMetrics();
      for (final metric in metrics) {
        const double step = 2.0; // шаг для дискретизации
        for (double dist = 0; dist <= metric.length; dist += step) {
          final tangent = metric.getTangentForOffset(dist);
          if (tangent != null) {
            final point = tangent.position;
            final distance = (localPos - point).distance;
            if (distance < minDistForConn) {
              minDistForConn = distance;
            }
          }
        }
        // Проверка конечной точки
        final endPoint = metric.getTangentForOffset(metric.length)?.position;
        if (endPoint != null) {
          final distance = (localPos - endPoint).distance;
          if (distance < minDistForConn) minDistForConn = distance;
        }
      }
      if (minDistForConn < minDistance) {
        minDistance = minDistForConn;
        tappedConnection = conn;
      }
    }

    if (tappedConnection != null) {
      setState(() {
        _selectedConnectionId = tappedConnection?.id;
        _selectedNodeNames.clear();
      });
      _isSelectingFromEmpty = false;
      return;
    }

    // Если не попали ни в блок, ни в точку, ни в линию
    final isOverNode = _isPointOverAnyNode(localPos);
    _isSelectingFromEmpty = !isOverNode;

    if (!isOverNode) {
      setState(() {
        _selectedNodeNames.clear();
        _selectedConnectionId = null;
      });
    }
  }

  // Контекстное меню узла
  void _showNodeContextMenu(TapDownDetails details, String nodeName) {
    final node = _controller.nodes[nodeName];
    final bool isProtected =
        node?.data is TerminalBlock &&
        (node!.data.text == 'Start' || node.data.text == 'End');

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        if (!isProtected)
          PopupMenuItem(value: 'delete', child: const Text('Удалить блок')),
      ],
    ).then((value) {
      if (value == 'delete') {
        _controller.removeNode(nodeName);
      }
    });
  }

  // Диалог редактирования текста блока
  Future<void> _editNodeText(String nodeName) async {
    final nodeData = _controller.nodes[nodeName];
    if (nodeData == null) return;
    final currentText = nodeData.data.text;
    final controller = TextEditingController(text: currentText);
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать текст блока'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Введите текст'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (newText != null && newText.isNotEmpty && newText != currentText) {
      _controller.updateNodeText(nodeName, newText);
    }
  }

  bool _isSaving = false;

  // Печатает текущую раскладку блок-схемы в консоль в виде дерева:
  //
  //   Rank 0:  Start         (col 0)
  //   Rank 1:  Cond1         (col 0)
  //   Rank 2:  A             (col 0)
  //            └─ no → X     (col 1)
  //   Rank 3:  End           (col 0)
  //
  // Rank считается из вертикальной позиции, col - из горизонтальной.
  void _dumpLayout() {
    debugPrint(
      '[layout] stepX=${_controller.spacing.stepX} '
      'stepY=${_controller.spacing.stepY} '
      'depth=${LayoutEngine.maxForDepth(_controller.graph)}',
    );
    final graph = _controller.graph;
    final nodes = graph.nodes;
    if (nodes.isEmpty) {
      debugPrint('[layout] empty graph');
      return;
    }

    // ── Счётчики детей для каждого узла ──────────────────────────────
    final directChildren = <String, int>{};
    final subtreeSize = <String, int>{};
    final bodySubtreeSize = <String, int>{};
    final exitSubtreeSize = <String, int>{};

    for (final name in nodes.keys) {
      final outs = (graph.outgoing[name] ?? const <ConnectionData>[])
          .where((c) => c.targetPort != 'loopback')
          .toList();
      directChildren[name] = outs.length;
      subtreeSize[name] = _countSubtree(graph, name);
      if (nodes[name]!.data is ForBlock) {
        bodySubtreeSize[name] = _countBodySubtree(graph, name);
        exitSubtreeSize[name] = _countExitSubtree(graph, name);
      }
    }

    final start = graph.findStart();
    if (start == null) {
      debugPrint('[layout] no Start node');
      return;
    }

    final size = _controller.nodeSize;
    final stepX = size.width + LayoutConstants.stepXExtra;
    final stepY = size.height + LayoutConstants.stepYExtra;

    String labelOf(String name) {
      final n = nodes[name];
      if (n == null) return name;
      final t = n.data.text;
      return t.isEmpty ? name : t;
    }

    // rank -> [(nodeName, label, col)]
    final byRank = <int, List<(String, String, int)>>{};
    for (final e in nodes.entries) {
      final pos = e.value.position;
      final rank = ((pos.dy - start.position.dy) / stepY).round();
      final col = ((pos.dx - start.position.dx) / stepX).round();
      byRank.putIfAbsent(rank, () => []).add((e.key, labelOf(e.key), col));
    }

    // для каждой цели - порт входящего ребра (out/yes/no/body/exit/in)
    final inPort = <String, String>{};
    for (final c in graph.connections) {
      inPort[c.targetNodeName] = c.sourcePort;
    }

    // ширина колонки под подписи - по самому длинному тексту
    final labelWidth = byRank.values
        .expand((row) => row)
        .map((r) => r.$2.length)
        .fold<int>(8, (a, b) => a > b ? a : b);

    const rankPrefixWidth = 10; // 'Rank 00:  '

    debugPrint('────── Layout dump ──────');
    final ranks = byRank.keys.toList()..sort();
    for (final r in ranks) {
      final row = byRank[r]!..sort((a, b) => a.$3.compareTo(b.$3));
      for (var i = 0; i < row.length; i++) {
        final (nodeName, label, col) = row[i];
        final namePadded = label.padRight(labelWidth);

        // Счётчики детей
        final sb = StringBuffer();
        sb.write(' ch=${directChildren[nodeName]}');
        sb.write(' sub=${subtreeSize[nodeName]}');
        if (nodes[nodeName]!.data is ForBlock) {
          sb.write(' body=${bodySubtreeSize[nodeName] ?? 0}');
          sb.write(' exit=${exitSubtreeSize[nodeName] ?? 0}');
        }
        final stats = sb.toString();

        if (i == 0) {
          // main-строка ранга
          final prefix = 'Rank $r:'.padRight(rankPrefixWidth);
          debugPrint('$prefix$namePadded (col $col)$stats');
        } else {
          // no
          final port = inPort[nodeName] ?? '?';
          final branch = i == row.length - 1 ? '└─' : '├─';
          final indent = ' ' * rankPrefixWidth;
          debugPrint('$indent$branch $port → $namePadded (col $col)$stats');
        }
      }
    }
    debugPrint('Edges:');

    for (final c in graph.connections) {
      debugPrint(
        '  ${c.sourceNodeName} --${c.sourcePort}--> ${c.targetNodeName}',
      );
    }
    debugPrint('─────────────────────────');
  }

  /// «Дети» по определению:
  ///  • ForBlock    — всё, что лежит в body (без перехода по exit);
  ///  • LogicBlock  — узлы по yes-ветке до слияния с no-веткой
  ///                  (сама точка слияния — не ребёнок);
  ///  • остальные   — 0.
  static int _countChildren(FlowchartGraph g, String nodeName) {
    final node = g.nodes[nodeName];
    if (node == null) return 0;

    if (node.data is ForBlock) {
      return _countBodySubtree(g, nodeName);
    }
    if (node.data is LogicBlock) {
      return _countYesBranchChildren(g, nodeName);
    }
    return 0;
  }

  /// yes-ветка условия: BFS от yes-цели, с остановкой на любом узле,
  /// достижимом из no-ветки (это и есть merge-точка), и на End.
  static int _countYesBranchChildren(FlowchartGraph g, String logicName) {
    ConnectionData? yesConn;
    ConnectionData? noConn;
    for (final c in g.outgoing[logicName] ?? const <ConnectionData>[]) {
      if (c.sourcePort == 'yes') yesConn = c;
      if (c.sourcePort == 'no') noConn = c;
    }
    if (yesConn == null || noConn == null) return 0;

    // Обе ветки сразу сходятся в одну и ту же точку → детей нет.
    if (yesConn.targetNodeName == noConn.targetNodeName) return 0;

    // Множество узлов, достижимых из no-ветки, — это «запрещённая зона».
    final noReachable = <String>{};
    final noQueue = <String>[noConn.targetNodeName];
    while (noQueue.isNotEmpty) {
      final cur = noQueue.removeAt(0);
      if (!noReachable.add(cur)) continue;
      if (g.isEnd(cur)) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        noQueue.add(c.targetNodeName);
      }
    }

    // Идём по yes-ветке, но упираемся на первом узле, который есть в no-зоне.
    final visited = <String>{};
    final queue = <String>[yesConn.targetNodeName];
    int count = 0;
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      if (noReachable.contains(cur)) continue; // merge-точка — стоп
      if (g.isEnd(cur)) continue;
      count++;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        queue.add(c.targetNodeName);
      }
    }
    return count;
  }

  /// Полное поддерево: BFS по исходящим рёбрам, без loopback,
  /// с остановкой на End. Возвращает количество потомков (без самого root).
  static int _countSubtree(FlowchartGraph g, String root) {
    final visited = <String>{};
    final queue = <String>[root];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      if (g.isEnd(cur)) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        queue.add(c.targetNodeName);
      }
    }
    return visited.length - 1; // без root
  }

  /// Поддерево тела For-блока: обходит только body-ветку,
  /// не переходя по exit-рёбрам вложенных For.
  static int _countBodySubtree(FlowchartGraph g, String forName) {
    ConnectionData? bodyConn;
    for (final c in g.outgoing[forName] ?? const <ConnectionData>[]) {
      if (c.sourcePort == 'body') {
        bodyConn = c;
        break;
      }
    }
    if (bodyConn == null) return 0;

    final visited = <String>{};
    final queue = <String>[bodyConn.targetNodeName];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      if (g.isEnd(cur)) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        if (c.sourcePort == 'exit') continue;
        queue.add(c.targetNodeName);
      }
    }
    return visited.length;
  }

  /// Поддерево выхода For-блока: BFS от exit-цели,
  /// до первого End или merge-точки (incoming > 1).
  static int _countExitSubtree(FlowchartGraph g, String forName) {
    ConnectionData? exitConn;
    for (final c in g.outgoing[forName] ?? const <ConnectionData>[]) {
      if (c.sourcePort == 'exit') {
        exitConn = c;
        break;
      }
    }
    if (exitConn == null) return 0;

    final visited = <String>{};
    final queue = <String>[exitConn.targetNodeName];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      if (g.isEnd(cur)) continue;
      // Останавливаемся на merge-точке — за ней начинается общий хвост
      if ((g.incoming[cur] ?? const []).length > 1) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        queue.add(c.targetNodeName);
      }
    }
    return visited.length;
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить схему?'),
        content: const Text(
          'Все несохраненные изменения будут удалены. Это действие можно отменить (Ctrl+Z).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      _controller.clearDiagram();
    }
  }

  Future<void> _saveToDb() async {
    _dumpLayout();
    final onSave = widget.onSave;
    if (onSave == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сохранение недоступно: экран открыт без проекта'),
        ),
      );
      return;
    }
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      final snapshot = _controller.toSnapshot();
      final previewSvg = SvgExporter.export(
        graph: _controller.graph,
        router: _router,
        nodeSize: _controller.nodeSize,
        spacing: _controller.spacing,
        canvasSize: _getContentSize(),
        showGrid: _controller.showGrid,
      );
      debugPrint('Generated SVG length: ${previewSvg.length}');

      await onSave(snapshot, previewSvg);
      // FlowchartEditorPage уже показывает snackbar «Схема сохранена»,
      // но на всякий случай продублируем — необязательно.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Сохраняет схему в JSON-файл в каталоге документов приложения
  // Future<void> _saveToJson() async {
  //   final snapshot = _controller.toSnapshot();
  //   final json = jsonEncode(snapshot.toJson());
  //   final directory = await getApplicationDocumentsDirectory();
  //   final file = File('${directory.path}/diagram.json');
  //   await file.writeAsString(json);
  //   ScaffoldMessenger.of(
  //     context,
  //   ).showSnackBar(SnackBar(content: Text('Схема сохранена: ${file.path}')));
  // }

  Future<void> _loadFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final bytes = picked.bytes;

      String content;
      if (bytes != null) {
        content = utf8.decode(bytes);
      } else if (picked.path != null) {
        // desktop fallback
        content = await File(picked.path!).readAsString();
      } else {
        throw Exception('Не удалось прочитать файл');
      }

      final jsonMap = jsonDecode(content) as Map<String, dynamic>;
      final snapshot = EditorSnapshot.fromJson(jsonMap);

      _controller.fromSnapshot(snapshot); // внутри уже notifyListeners()
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Схема загружена')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
    }
  }

  // Загружает схему из JSON-файла в каталоге документов
  // Future<void> _loadFromJson() async {
  //   try {
  //     final directory = await getApplicationDocumentsDirectory();
  //     final file = File('${directory.path}/diagram.json');
  //     if (!await file.exists()) throw Exception('Файл не найден');
  //     final jsonString = await file.readAsString();
  //     final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
  //     final snapshot = EditorSnapshot.fromJson(jsonMap);
  //     _controller.fromSnapshot(snapshot);
  //     ScaffoldMessenger.of(
  //       context,
  //     ).showSnackBar(const SnackBar(content: Text('Схема загружена')));
  //   } catch (e) {
  //     ScaffoldMessenger.of(
  //       context,
  //     ).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
  //   }
  // }
  //
  Future<String?> _askFileName(String title) async {
    final controller = TextEditingController(text: 'diagram');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Имя файла'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    final name = controller.text.trim();
    return name.isEmpty ? 'diagram' : name;
  }

  Future<void> _exportToSvg() async {
    if (_controller.nodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет элементов для экспорта')),
      );
      return;
    }

    final name = await _askFileName('Экспорт в SVG');
    if (name == null) return;
    // Чистый экспорт - только строка
    final svg = SvgExporter.export(
      graph: _controller.graph,
      router: _router,
      nodeSize: _controller.nodeSize,
      spacing: _controller.spacing,
      canvasSize: _getContentSize(),
      showGrid: _controller.showGrid,
    );

    try {
      await FileSaver.instance.saveFile(
        name: name, // без расширения
        bytes: utf8.encode(svg),
        ext: 'svg',
        mimeType: MimeType.other,
        customMimeType: 'image/svg+xml',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Файл $name.svg сохранён')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
    }
  }

  Future<void> _exportToJson() async {
    if (_controller.nodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет элементов для экспорта')),
      );
      return;
    }

    final name = await _askFileName('Экспорт в JSON');
    if (name == null) return;

    final json = jsonEncode(_controller.toSnapshot().toJson());

    try {
      await FileSaver.instance.saveFile(
        name: name,
        bytes: utf8.encode(json),
        ext: 'json',
        mimeType: MimeType.json,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Файл $name.json сохранён')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
    }
  }

  // Строит виджет одного узла
  Widget _buildNodeWidget(String nodeName, NodeModel data, bool readOnly) {
    final isSelected = !readOnly && _selectedNodeNames.contains(nodeName);

    return Positioned(
      left: data.position.dx,
      top: data.position.dy,
      child: GestureDetector(
        onTap: readOnly
            ? null
            : () {
                setState(() {
                  _selectedNodeNames = {nodeName};
                  _selectedConnectionId = null;
                });
                _focusNode.requestFocus();
              },
        onDoubleTap: readOnly ? null : () => _editNodeText(nodeName),
        onSecondaryTapDown: readOnly
            ? null
            : (details) => _showNodeContextMenu(details, nodeName),
        child: GostNodeBuilder(
          nodeSize: _controller.nodeSize,
          isSelected: isSelected,
          onResize: readOnly
              ? (_) {}
              : (newSize) => _controller.setNodeSize(newSize),
          onPositionChange: readOnly
              ? (_, __) {}
              : (name, newPosition) =>
                    _controller.updateNodePosition(name, newPosition),

          nodeName: nodeName,
        ).build(data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // мобильное ли устройство
    final isMobile = MediaQuery.sizeOf(context).width < 800;
    // В мобильном режиме - только для чтения
    final readOnly = isMobile;

    final contentSize = _getContentSize();
    final graph = _controller.graph;
    final nodes = graph.nodes;
    final nodeSize = _controller.nodeSize;
    final showGrid = _controller.showGrid;
    final scale = _controller.scale;
    final toolbarVisible = !readOnly && _controller.isToolbarVisible;

    // Виджет сетки с подписями
    final startNodeEntry = nodes.entries.firstWhereOrNull(
      (e) => e.value.data is TerminalBlock && e.value.data.text == 'Start',
    );
    final startPos = startNodeEntry?.value.position;

    Widget gridWidget = const SizedBox.shrink();
    if (showGrid && startNodeEntry != null) {
      gridWidget = GridWithLabels(
        canvasSize: contentSize,
        columnWidth: _controller.spacing.stepX,
        rowHeight: _controller.spacing.stepY,
        nodeWidth: _controller.nodeSize.width,
        nodeHeight: _controller.nodeSize.height,
        startPosition: startNodeEntry.value.position,
      );
    }

    final leftInset = toolbarVisible ? 200.0 : 40.0;
    final bottomInset = isMobile ? 20.0 : 0.0; // высота _BottomScrollBar
    final showSticky = showGrid && startNodeEntry != null;

    return Scaffold(
      body: Stack(
        children: [
          // Левая панель инструментов
          if (toolbarVisible)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: RepaintBoundary(
                child: SizedBox(
                  width: 200,
                  child: VerticalToolbar(
                    selectedPrototype: _selectedPrototype,
                    onSelectPrototype: (p) =>
                        setState(() => _selectedPrototype = p),
                    onSetNodeSize: _controller.setNodeSize,
                    isGridVisible: showGrid,
                    onGridToggle: _controller.setShowGrid,
                    onExport: _exportToSvg,
                    onExportJson: _exportToJson,
                    onUndo: _controller.undo,
                    onRedo: _controller.redo,
                    onSave: _saveToDb,
                    canSave: widget.canSave && widget.onSave != null,
                    onLoad: _loadFromFile,
                    isSaving: _isSaving,
                    onClear: _confirmClear,
                    currentNodeSize: _controller.nodeSize,
                  ),
                ),
              ),
            ),

          // Область холста
          Row(
            children: [
              SizedBox(width: toolbarVisible ? 200 : 40),
              Expanded(
                // Двухуровневая прокрутка: вертикальная + горизонтальная
                child: Scrollbar(
                  thumbVisibility: !isMobile,
                  trackVisibility: !isMobile,
                  controller: _horizontalScrollController,
                  child: SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.vertical,
                    child: Scrollbar(
                      thumbVisibility: !isMobile,
                      trackVisibility: !isMobile,
                      controller: _verticalScrollController,
                      child: SingleChildScrollView(
                        controller: _verticalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentSize.width * scale,
                          height: contentSize.height * scale,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerSignal: _handleZoomSignal,
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: 0,
                              maxWidth: double.infinity,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: Transform.scale(
                                scale: scale,
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  width: contentSize.width,
                                  height: contentSize.height,
                                  child: MouseRegion(
                                    onHover: (event) =>
                                        _handleCanvasHover(event.localPosition),
                                    onExit: (_) => _handleCanvasHover(null),
                                    child: GestureDetector(
                                      // Тап по холсту: выбор точки вставки, линии или сброс выделения
                                      onTapDown: readOnly
                                          ? null
                                          : _handleCanvasTapDown,
                                      onTap: readOnly
                                          ? null
                                          : () {
                                              setState(() {
                                                // _selectedNodeName = null;
                                                _selectedNodeNames.clear();
                                                _selectedConnectionId = null;
                                                _selectionStart = null;
                                                _selectionEnd = null;
                                                _isSelecting = false;
                                              });
                                              _focusNode.requestFocus();
                                            },
                                      onPanStart: readOnly
                                          ? null
                                          : (details) {
                                              // Начинаем выделение, только если касание было по пустой области
                                              if (!_isSelectingFromEmpty)
                                                return;
                                              setState(() {
                                                _isSelecting = true;
                                                _selectionStart =
                                                    details.localPosition;
                                                _selectionEnd =
                                                    details.localPosition;
                                              });
                                            },
                                      onPanUpdate: readOnly
                                          ? null
                                          : (details) {
                                              if (!_isSelecting) return;
                                              setState(() {
                                                _selectionEnd =
                                                    details.localPosition;
                                              });
                                            },
                                      // Завершение выделения - выбрать все блоки, пересекающиеся с рамкой
                                      onPanEnd: readOnly
                                          ? null
                                          : (details) {
                                              if (!_isSelecting) return;
                                              final rect = Rect.fromPoints(
                                                _selectionStart!,
                                                _selectionEnd!,
                                              );
                                              // Выделить все блоки, пересекающиеся с rect
                                              final newSelection = <String>{};
                                              for (final entry
                                                  in nodes.entries) {
                                                final nodePos =
                                                    entry.value.position;
                                                final nodeRect = Rect.fromLTWH(
                                                  nodePos.dx,
                                                  nodePos.dy,
                                                  nodeSize.width,
                                                  nodeSize.height,
                                                );
                                                if (rect.overlaps(nodeRect)) {
                                                  newSelection.add(entry.key);
                                                }
                                              }
                                              setState(() {
                                                _selectedNodeNames =
                                                    newSelection;
                                                _selectionStart = null;
                                                _selectionEnd = null;
                                                _isSelecting = false;
                                              });
                                              _focusNode.requestFocus();
                                            },
                                      child: Focus(
                                        focusNode: _focusNode,
                                        autofocus: true,
                                        onKeyEvent: readOnly
                                            ? null
                                            : (node, event) {
                                                _handleKeyEvent(event);
                                                return KeyEventResult.ignored;
                                              },
                                        child: CustomPaint(
                                          child: Stack(
                                            children: [
                                              // Сетка
                                              if (showGrid) gridWidget,
                                              // Линии соединений
                                              CustomPaint(
                                                painter: ConnectionPainter(
                                                  graph: graph,
                                                  router: _router,
                                                  selectedConnectionId:
                                                      _selectedConnectionId,
                                                  hoveredConnectionId:
                                                      _hoveredConnectionId,
                                                  insertionPoints: readOnly
                                                      ? const <InsertionPoint>[]
                                                      : _insertionPoints,
                                                ),
                                                child: Stack(
                                                  children: nodes.entries
                                                      .map(
                                                        (entry) =>
                                                            _buildNodeWidget(
                                                              entry.key,
                                                              entry.value,
                                                              readOnly,
                                                            ),
                                                      )
                                                      .toList(),
                                                ),
                                              ),
                                              // Прямоугольник выделения
                                              if (_isSelecting &&
                                                  _selectionStart != null &&
                                                  _selectionEnd != null)
                                                CustomPaint(
                                                  painter: SelectionRectPainter(
                                                    start: _selectionStart!,
                                                    end: _selectionEnd!,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // ),
            ],
          ),

          if (showSticky) ...[
            // Угол
            Positioned(
              top: 0,
              left: leftInset,
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    right: BorderSide(color: Colors.grey.shade300),
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),
            // Цифры столбцов
            Positioned(
              top: 0,
              left: leftInset,
              right: 0,
              height: 22,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: AnimatedBuilder(
                    animation: _verticalScrollController,
                    builder: (_, _) => CustomPaint(
                      painter: ColumnHeadersPainter(
                        scrollOffset: _safeOffset(_verticalScrollController),
                        columnWidth: _controller.spacing.stepX,
                        nodeWidth: _controller.nodeSize.width,
                        startPositionX: startPos!.dx,
                        scale: _controller.scale,
                        textStyle: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Буквы строк
            Positioned(
              top: 0,
              left: leftInset,
              width: 22,
              bottom: bottomInset,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: AnimatedBuilder(
                    animation: _horizontalScrollController,
                    builder: (_, _) => CustomPaint(
                      painter: RowHeadersPainter(
                        scrollOffset: _safeOffset(_horizontalScrollController),
                        rowHeight: _controller.spacing.stepY,
                        nodeHeight: _controller.nodeSize.height,
                        startPositionY: startPos!.dy,
                        scale: _controller.scale,
                        textStyle: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // Кнопка сворачивания/разворачивания панели
          if (!readOnly)
            Positioned(
              bottom: 18,
              left: toolbarVisible ? 200 - 40 : 8,
              child: FloatingActionButton.small(
                heroTag: null,
                backgroundColor: Colors.grey.shade200,
                foregroundColor: Colors.grey.shade700,
                splashColor: Colors.grey.shade300,
                onPressed: () => _controller.setToolbarVisible(!toolbarVisible),
                child: Icon(
                  toolbarVisible ? Icons.chevron_left : Icons.chevron_right,
                ),
              ),
            ),

          // Горизонтальный скроллбар внизу экрана на мобиле
          if (isMobile)
            Positioned(
              left: leftInset,
              right: 0,
              bottom: 0,
              child: Material(
                color: Colors.white,
                elevation: 2,
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 20,
                    child: _BottomScrollBar(
                      controller: _verticalScrollController,
                    ),
                  ),
                ),
              ),
            ),
          if (widget.onBack != null)
            Positioned(
              top: 18,
              left: readOnly ? 8 : (toolbarVisible ? 200 + 16 : 56),
              child: FloatingActionButton.small(
                heroTag: null,
                onPressed: widget.onBack,
                child: Icon(Icons.arrow_back),
              ),
            ),
        ],
      ),
    );
  }
}

class GridWithLabels extends StatelessWidget {
  final Size canvasSize;
  final double columnWidth;
  final double rowHeight;
  final double nodeWidth;
  final double nodeHeight;
  final Offset? startPosition;

  const GridWithLabels({
    super.key,
    required this.canvasSize,
    required this.columnWidth,
    required this.rowHeight,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.startPosition,
  });

  @override
  Widget build(BuildContext context) {
    if (startPosition == null) return const SizedBox.shrink();
    return CustomPaint(
      size: canvasSize,
      painter: GridLabelsPainter(
        columnWidth: columnWidth,
        rowHeight: rowHeight,
        nodeWidth: nodeWidth,
        nodeHeight: nodeHeight,
        startPosition: startPosition!,
      ),
    );
  }
}

class _BottomScrollBar extends StatelessWidget {
  final ScrollController controller;

  const _BottomScrollBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final positions = controller.positions;
        if (positions.isEmpty) {
          return const SizedBox(height: 20, width: double.infinity);
        }
        final pos = positions.first;
        if (!pos.hasContentDimensions ||
            !pos.hasViewportDimension ||
            !pos.hasPixels) {
          return const SizedBox(height: 20, width: double.infinity);
        }
        final max = pos.maxScrollExtent;
        final viewport = pos.viewportDimension;
        final total = max + viewport;
        if (max <= 0 || total <= 0) {
          return const SizedBox(height: 20, width: double.infinity);
        }

        final thumbFraction = (viewport / total).clamp(0.0, 1.0);
        final scrollFraction = (pos.pixels / max).clamp(0.0, 1.0);

        return LayoutBuilder(
          builder: (context, constraints) {
            const hPadding = 4.0;
            final trackWidth = constraints.maxWidth - hPadding * 2;
            if (trackWidth <= 0) {
              return const SizedBox(height: 20, width: double.infinity);
            }

            final thumbWidth = (trackWidth * thumbFraction).clamp(
              40.0,
              trackWidth,
            );
            final maxThumbLeft = trackWidth - thumbWidth;
            final thumbLeft = hPadding + maxThumbLeft * scrollFraction;

            void seekTo(double localX) {
              if (maxThumbLeft <= 0) return;
              final target = (localX - hPadding - thumbWidth / 2).clamp(
                0.0,
                maxThumbLeft,
              );
              final pixels = (target / maxThumbLeft) * max;
              controller.jumpTo(pixels.clamp(0.0, max));
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => seekTo(d.localPosition.dx),
              onHorizontalDragStart: (d) => seekTo(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
              child: SizedBox(
                height: 20,
                child: Stack(
                  children: [
                    Positioned(
                      left: hPadding,
                      right: hPadding,
                      top: 8,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Positioned(
                      left: thumbLeft,
                      top: 4,
                      bottom: 4,
                      width: thumbWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
