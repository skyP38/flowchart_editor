import 'package:flowchart_editor_frontend/features/editor/factories/node_factory.dart';
import 'package:flowchart_editor_frontend/features/editor/state/flow_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:collection/collection.dart';
import '../models/flow_models.dart';
import '../widgets/gost_node_builder.dart';
import '../widgets/vertical_toolbar.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
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

// Главный экран редактора блок-схем
class EditorScreen extends StatefulWidget {
  final EditorSnapshot? initialSnapshot;
  final Future<void> Function(EditorSnapshot snapshot)? onSave;

  const EditorScreen({super.key, this.initialSnapshot, this.onSave});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
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

  late final ConnectionRouter _router;
  late final InsertionPointsService _insertionPointsService;
  Size _lastNodeSize = Size.zero;

  @override
  void initState() {
    super.initState();
    if (widget.initialSnapshot != null) {
      _controller.fromSnapshot(widget.initialSnapshot!);
    } else {
      _controller.initDefaultDiagram();
    }
    // _controller.initDefaultDiagram();
    _rebuildRouter();
    _insertionPoints = _insertionPointsService.compute(_controller.graph);
    _controller.addListener(_onControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  // Пересобирает роутер и сервис точек вставки под текущий размер блока
  void _rebuildRouter() {
    final size = _controller.nodeSize;
    _lastNodeSize = size;
    _router = ConnectionRouter(
      nodeSize: size,
      spacing: LayoutSpacing(
        stepX: size.width + LayoutConstants.stepXExtra,
        stepY: size.height + LayoutConstants.stepYExtra,
      ),
    );
    _insertionPointsService = InsertionPointsService(router: _router);
  }

  // Реакция на изменение контроллера
  void _onControllerChanged() {
    if (!mounted) return;

    if (_controller.nodeSize != _lastNodeSize) {
      _rebuildRouter();
    }

    setState(() {
      _insertionPoints = _insertionPointsService.compute(_controller.graph);
    });
  }

  List<InsertionPoint> _computeInsertionPoints() =>
      _insertionPointsService.compute(_controller.graph);

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
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

    // return Size(width * _scale, height * _scale);
    return Size(width, height);
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
    // final hw = HardwareKeyboard.instance;
    // _pushState();

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
    for (final point in _insertionPoints) {
      if ((localPos - point.position).distance <= 12.0) {
        if (_selectedPrototype != null) {
          _controller.insertNodeOnConnection(
            point.connection.id!,
            _selectedPrototype!,
          );
          setState(() => _selectedPrototype = null);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Выберите тип блока на панели слева')),
          );
        }
        _isSelectingFromEmpty = false;
        return;
      }
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

  // Сохраняет схему в JSON-файл в каталоге документов приложения
  Future<void> _saveToJson() async {
    final snapshot = _controller.toSnapshot();
    final json = jsonEncode(snapshot.toJson());
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/diagram.json');
    await file.writeAsString(json);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Схема сохранена: ${file.path}')));
  }

  // Загружает схему из JSON-файла в каталоге документов
  Future<void> _loadFromJson() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/diagram.json');
      if (!await file.exists()) throw Exception('Файл не найден');
      final jsonString = await file.readAsString();
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      final snapshot = EditorSnapshot.fromJson(jsonMap);
      _controller.fromSnapshot(snapshot);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Схема загружена')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
    }
  }

  Future<void> _exportToSvg() async {
    if (_controller.nodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет элементов для экспорта')),
      );
      return;
    }

    // Диалог имени файла
    final fileNameController = TextEditingController(text: 'diagram');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Экспорт в SVG'),
        content: TextField(
          controller: fileNameController,
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
    if (confirmed != true) return;

    // Чистый экспорт — только строка
    final svg = SvgExporter.export(
      graph: _controller.graph,
      router: _router,
      nodeSize: _controller.nodeSize,
      canvasSize: _getContentSize(),
      showGrid: _controller.showGrid,
    );

    try {
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        throw Exception('Не удалось получить директорию для сохранения');
      }
      final file = File('${directory.path}/${fileNameController.text}.svg');
      await file.writeAsString(svg);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Схема сохранена: ${file.path}')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
    }
  }

  // Строит виджет одного узла
  Widget _buildNodeWidget(String nodeName, NodeModel data) {
    final isSelected = _selectedNodeNames.contains(nodeName);

    return Positioned(
      left: data.position.dx,
      top: data.position.dy,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedNodeNames = {nodeName};
            _selectedConnectionId = null;
          });
          _focusNode.requestFocus();
        },
        onDoubleTap: () => _editNodeText(nodeName),
        onSecondaryTapDown: (details) =>
            _showNodeContextMenu(details, nodeName),
        child: GostNodeBuilder(
          nodeSize: _controller.nodeSize,
          isSelected: isSelected,
          onResize: (newSize) => _controller.setNodeSize(newSize),
          onPositionChange: (name, newPosition) =>
              _controller.updateNodePosition(name, newPosition),

          nodeName: nodeName,
        ).build(data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentSize = _getContentSize();
    final graph = _controller.graph;
    final nodes = graph.nodes;
    final connections = graph.connections;
    final nodeSize = _controller.nodeSize;
    final showGrid = _controller.showGrid;
    final scale = _controller.scale;
    final toolbarVisible = _controller.isToolbarVisible;

    // Виджет сетки с подписями
    Widget gridWidget = const SizedBox.shrink();
    if (showGrid) {
      final startNodeEntry = nodes.entries.firstWhereOrNull(
        (e) => e.value.data is TerminalBlock && e.value.data.text == 'Start',
      );
      if (startNodeEntry != null) {
        gridWidget = GridWithLabels(
          canvasSize: contentSize,
          stepX: nodeSize.width,
          stepY: nodeSize.height,
          startPosition: startNodeEntry.value.position,
        );
      }
    }

    // Создание контроллера для вертикальной прокрутки
    // final verticalScrollController = ScrollController();
    // Для горизонтальной прокрутки
    // final horizontalScrollController = ScrollController();
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
                    onUndo: _controller.undo,
                    onRedo: _controller.redo,
                    onSave: _saveToJson,
                    onLoad: _loadFromJson,
                  ),
                ),
              ),
            ),

          // Кнопка сворачивания/разворачивания панели
          Positioned(
            top: 18,
            left: toolbarVisible ? 200 - 40 : 8,
            child: FloatingActionButton.small(
              heroTag: null,
              onPressed: () => _controller.setToolbarVisible(!toolbarVisible),
              child: Icon(
                toolbarVisible ? Icons.chevron_left : Icons.chevron_right,
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
                  thumbVisibility: true,
                  trackVisibility: true, // всегда показывать дорожку полосы
                  controller: _verticalScrollController,
                  child: SingleChildScrollView(
                    controller: _verticalScrollController,
                    scrollDirection: Axis.vertical,
                    child: Scrollbar(
                      thumbVisibility: true,
                      trackVisibility:
                          true, // дорожка для горизонтальной полосы
                      controller: _horizontalScrollController,
                      child: SingleChildScrollView(
                        controller: _horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentSize.width,
                          height: contentSize.height,
                          child: Listener(
                            onPointerSignal: (event) {
                              final hw = HardwareKeyboard.instance;
                              if (!(hw.isControlPressed || hw.isMetaPressed)) {
                                return;
                              }

                              double delta = 0;
                              bool handled = false;

                              try {
                                final dynamic sd =
                                    (event as dynamic).scrollDelta;
                                if (sd != null) {
                                  delta = (sd.dy as num).toDouble();
                                  handled = true;
                                }
                              } catch (_) {}
                              if (!handled) {
                                try {
                                  final dynamic s = (event as dynamic).scale;
                                  if (s != null) {
                                    delta = (1.0 - (s as num).toDouble()) * 100;
                                    handled = true;
                                  }
                                } catch (_) {}
                              }

                              if (!handled || delta == 0) return;

                              final newScale = (scale + delta * -0.01).clamp(
                                _minScale,
                                _maxScale,
                              );
                              _controller.setScale(newScale);
                            },
                            child: Transform(
                              transform: Matrix4.diagonal3Values(
                                scale,
                                scale,
                                1.0,
                              ),
                              child: GestureDetector(
                                // Тап по холсту: выбор точки вставки, линии или сброс выделения
                                onTapDown: _handleCanvasTapDown,
                                onTap: () {
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
                                onPanStart: (details) {
                                  // Начинаем выделение, только если касание было по пустой области
                                  if (!_isSelectingFromEmpty) return;
                                  setState(() {
                                    _isSelecting = true;
                                    _selectionStart = details.localPosition;
                                    _selectionEnd = details.localPosition;
                                  });
                                },
                                onPanUpdate: (details) {
                                  if (!_isSelecting) return;
                                  setState(() {
                                    _selectionEnd = details.localPosition;
                                  });
                                },
                                // Завершение выделения - выбрать все блоки, пересекающиеся с рамкой
                                onPanEnd: (details) {
                                  if (!_isSelecting) return;
                                  final rect = Rect.fromPoints(
                                    _selectionStart!,
                                    _selectionEnd!,
                                  );
                                  // Выделить все блоки, пересекающиеся с rect
                                  final newSelection = <String>{};
                                  for (final entry in nodes.entries) {
                                    final nodePos = entry.value.position;
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
                                    _selectedNodeNames = newSelection;
                                    _selectionStart = null;
                                    _selectionEnd = null;
                                    _isSelecting = false;
                                  });
                                  _focusNode.requestFocus();
                                },
                                child: Focus(
                                  focusNode: _focusNode,
                                  autofocus: true,
                                  onKeyEvent: (node, event) {
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
                                            insertionPoints: _insertionPoints,
                                          ),
                                          child: Stack(
                                            children: nodes.entries
                                                .map(
                                                  (entry) => _buildNodeWidget(
                                                    entry.key,
                                                    entry.value,
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
            ],
          ),
        ],
      ),
    );
  }
}

/// Виджет с подписями сетки (буквы строк и цифры столбцов).
class GridWithLabels extends StatelessWidget {
  final Size canvasSize;
  final double stepX;
  final double stepY;
  final Offset? startPosition;

  const GridWithLabels({
    super.key,
    required this.canvasSize,
    required this.stepX,
    required this.stepY,
    required this.startPosition,
  });

  @override
  Widget build(BuildContext context) {
    if (startPosition == null) return const SizedBox.shrink();
    return CustomPaint(
      size: canvasSize,
      painter: GridLabelsPainter(
        stepX: stepX,
        stepY: stepY,
        startPosition: startPosition!,
      ),
    );
  }
}
