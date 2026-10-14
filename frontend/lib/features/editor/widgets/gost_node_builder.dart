import 'package:flutter/material.dart';
import '../factories/node_factory.dart';
import '../models/flow_models.dart';
import '../utils/node_shape_geometry.dart';

// Строит виджет блока в соответствии с ГОСТ
// Класс отвечает за визуальное представление узла
class GostNodeBuilder {
  // Текущий размер узла
  final Size nodeSize;
  // Признак того, что узел выделен
  final bool isSelected;
  // Колбэк, вызываемый при изменении размера узла
  final ValueChanged<Size> onResize;
  // Колбэк изменения позиции узла
  final void Function(String nodeName, Offset newPosition)? onPositionChange;
  // Колбэк начала процесса изменения размера
  final VoidCallback? onResizeStart;
  // Колбэк окончания процесса изменения размера
  final VoidCallback? onResizeEnd;
  // Имя узла
  final String nodeName;

  const GostNodeBuilder({
    required this.nodeSize,
    required this.isSelected,
    required this.onResize,
    this.onPositionChange,
    this.onResizeStart,
    this.onResizeEnd,
    required this.nodeName,
  });

  Widget build(NodeModel node) {
    final data = node.data;
    final text = data.text;

    final shape = _ShapeNode(
      size: nodeSize,
      data: data,
      overlay: data is LogicBlock
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  bottom: -20,
                  left: nodeSize.width / 2 - 25,
                  child: const Text(
                    'Да',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                Positioned(
                  right: -25,
                  top: nodeSize.height / 2 - 20,
                  child: const Text(
                    'Нет',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            )
          : null,
      child: _NodeContent(text: text),
    );

    if (isSelected) {
      return _ResizableWrapper(
        size: nodeSize,
        onResize: onResize,
        onPositionChange: (delta) {
          if (onPositionChange != null) {
            onPositionChange!(nodeName, node.position + delta);
          }
        },
        onResizeStart: onResizeStart,
        onResizeEnd: onResizeEnd,
        nodePosition: node.position,
        child: shape,
      );
    }

    return SizedBox(
      width: nodeSize.width,
      height: nodeSize.height,
      child: shape,
    );
  }
}

// Обертка над фигурой узла, добавляющая 8 маркеров ресайза
// и поддерживающая изменение размера и позиции узла
class _ResizableWrapper extends StatefulWidget {
  final Size size;
  final ValueChanged<Size> onResize;
  final ValueChanged<Offset> onPositionChange;
  final Widget child;
  final VoidCallback? onResizeStart;
  final VoidCallback? onResizeEnd;
  final Offset nodePosition;

  const _ResizableWrapper({
    required this.size,
    required this.onResize,
    required this.onPositionChange,
    required this.child,
    this.onResizeStart,
    this.onResizeEnd,
    required this.nodePosition,
  });

  @override
  State<_ResizableWrapper> createState() => _ResizableWrapperState();
}

class _ResizableWrapperState extends State<_ResizableWrapper> {
  // Текущий размер во время перетаскивания маркера
  late Size _size;
  // Прямоугольник на момент начала перетаскивания
  Rect? _startRect;
  Offset? _startDragPosition;
  // Активный маркер
  Alignment? _activeHandle;
  // Offset? _startNodePosition;
  Offset _tempTranslation = Offset.zero;

  @override
  void initState() {
    super.initState();
    _size = widget.size;
  }

  @override
  void didUpdateWidget(covariant _ResizableWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.size != oldWidget.size) {
      _size = widget.size;
      _tempTranslation = Offset.zero;
    }
  }

  // Строит один из восьми маркеров ресайза для указанного угла/стороны [align]
  // Возвращает [Positioned] с обработчиками жестов
  Widget _buildHandle(Alignment align) {
    final isActive = _activeHandle == align;

    // Расчет позиции маркера относительно фигуры
    double left, top;
    final effectiveWidth = _size.width;
    final effectiveHeight = _size.height;
    switch (align.x) {
      case -1:
        left = -14;
        break;
      case 0:
        left = effectiveWidth / 2 - 14;
        break;
      case 1:
        left = effectiveWidth - 12;
        break;
      default:
        left = -14;
    }
    switch (align.y) {
      case -1:
        top = -14;
        break;
      case 0:
        top = effectiveHeight / 2 - 14;
        break;
      case 1:
        top = effectiveHeight - 14;
        break;
      default:
        top = -14;
    }
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Начало перетаскивания маркера
        onPanStart: (details) {
          widget.onResizeStart?.call();
          setState(() {
            _activeHandle = align;
          });
          _startDragPosition = details.localPosition;
          _startRect = Rect.fromLTWH(
            widget.nodePosition.dx,
            widget.nodePosition.dy,
            _size.width,
            _size.height,
          );
          _tempTranslation = Offset.zero;
        },
        // Обработка смещения маркера
        onPanUpdate: (details) {
          if (_startRect == null || _startDragPosition == null) return;
          final delta = details.localPosition - _startDragPosition!;
          Rect newRect = _startRect!;

          // Изменение левой/правой границы
          if (align.x == -1) {
            newRect = Rect.fromLTRB(
              newRect.left + delta.dx,
              newRect.top,
              newRect.right,
              newRect.bottom,
            );
          } else if (align.x == 1) {
            newRect = Rect.fromLTRB(
              newRect.left,
              newRect.top,
              newRect.right + delta.dx,
              newRect.bottom,
            );
          }

          // Изменение верхней/нижней границы
          if (align.y == -1) {
            newRect = Rect.fromLTRB(
              newRect.left,
              newRect.top + delta.dy,
              newRect.right,
              newRect.bottom,
            );
          } else if (align.y == 1) {
            newRect = Rect.fromLTRB(
              newRect.left,
              newRect.top,
              newRect.right,
              newRect.bottom + delta.dy,
            );
          }

          // Ограничение минимальной ширины
          if (newRect.width < 80) {
            if (align.x == -1) {
              newRect = Rect.fromLTRB(
                newRect.right - 80,
                newRect.top,
                newRect.right,
                newRect.bottom,
              );
            } else {
              newRect = Rect.fromLTRB(
                newRect.left,
                newRect.top,
                newRect.left + 80,
                newRect.bottom,
              );
            }
          }
          // Ограничение минимальной высоты
          if (newRect.height < 40) {
            if (align.y == -1) {
              newRect = Rect.fromLTRB(
                newRect.left,
                newRect.bottom - 40,
                newRect.right,
                newRect.bottom,
              );
            } else {
              newRect = Rect.fromLTRB(
                newRect.left,
                newRect.top,
                newRect.right,
                newRect.top + 40,
              );
            }
          }

          setState(() {
            _size = newRect.size;
          });

          // Дельта позиции (для верхних/левых маркеров)
          final deltaPos = Offset(
            newRect.left - _startRect!.left,
            newRect.top - _startRect!.top,
          );
          if (deltaPos != Offset.zero) {
            setState(() {
              _tempTranslation = deltaPos;
            });
          }
        },
        // Завершение перетаскивания маркера: фиксируем размер и позицию
        onPanEnd: (details) {
          setState(() => _activeHandle = null);
          final finalDelta = _tempTranslation;
          widget.onPositionChange(finalDelta);
          widget.onResize(_size);
          widget.onResizeEnd?.call();
          // Сброс
          _startRect = null;
          _startDragPosition = null;
          _tempTranslation = Offset.zero;
        },
        // Визуализация самого маркера
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: isActive ? Colors.green : Colors.white,
                border: Border.all(
                  color: isActive ? Colors.green : Colors.blue,
                  width: isActive ? 3 : 2,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: _tempTranslation,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Сама фигура узла
          SizedBox(
            width: _size.width,
            height: _size.height,
            child: widget.child,
          ),
          // 8 маркеров ресайза по углам и серединам сторон
          _buildHandle(Alignment.topLeft),
          _buildHandle(Alignment.topCenter),
          _buildHandle(Alignment.topRight),
          _buildHandle(Alignment.centerLeft),
          _buildHandle(Alignment.centerRight),
          _buildHandle(Alignment.bottomLeft),
          _buildHandle(Alignment.bottomCenter),
          _buildHandle(Alignment.bottomRight),
        ],
      ),
    );
  }
}

// Внутреннее содержимое узла - текст с отступами
class _NodeContent extends StatelessWidget {
  final String text;
  const _NodeContent({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ShapeNode extends StatelessWidget {
  final Size size;
  final GostNodeData data;
  final Widget child;
  final Widget? overlay;

  const _ShapeNode({
    required this.size,
    required this.data,
    required this.child,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          // Контур + доп. линии
          Positioned.fill(
            child: CustomPaint(
              painter: _ShapePainter(
                outline: NodeShapeGeometry.outline(size, data),
                extras: NodeShapeGeometry.extras(size, data),
              ),
            ),
          ),
          // Текст (или любой другой child)
          Center(child: child),
          ?overlay,
        ],
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  final Path outline;
  final List<Path> extras;
  const _ShapePainter({required this.outline, required this.extras});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(outline, stroke);
    for (final e in extras) {
      canvas.drawPath(e, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter old) =>
      old.outline != outline || old.extras != extras;
}
