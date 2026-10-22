import 'package:flutter/material.dart';
import '../models/flow_models.dart';
import '../constants/diagram_constants.dart';

// Левая панель инструментов редактора
// Содержит:
//   - кнопки выбора прототипа;
//   - переключатель сетки;
//   - экспорт в SVG;
//   - undo/rendo/save/load.
class VerticalToolbar extends StatelessWidget {
  // Текущий выбранный прототип блока
  final GostNodeData? selectedPrototype;
  // Колбэк выбора/снятия прототипа
  final ValueChanged<GostNodeData?> onSelectPrototype;
  // Колбэк установки нового размера для всех блоков
  final ValueChanged<Size> onSetNodeSize;
  // Видима ли сейчас сетка на холсте
  final bool isGridVisible;
  // Колбэк переключения видимости сетки
  final ValueChanged<bool> onGridToggle;
  // Колбэк экспорта схемы
  final VoidCallback onExport;
  final VoidCallback onExportJson;

  // Колбэк отмены последнего действия
  final VoidCallback onUndo;
  // Колбэк возврата отмененного действия
  final VoidCallback onRedo;
  // Колбэк сохранения схемы
  final VoidCallback onSave;
  // Колбэк загрузки схемы
  final VoidCallback onLoad;

  final bool isSaving;

  final bool canSave;

  final VoidCallback onClear;

  final Size currentNodeSize;

  const VerticalToolbar({
    super.key,
    required this.selectedPrototype,
    required this.onSelectPrototype,
    required this.onSetNodeSize,
    required this.isGridVisible,
    required this.onGridToggle,
    required this.onExport,
    required this.onExportJson,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
    required this.onLoad,
    this.isSaving = false,
    this.canSave = true,
    required this.onClear,
    required this.currentNodeSize,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Кнопки выбора прототипов блоков
            _buildButton(
              label: 'Process',
              prototype: ProcessBlock(''),
              shape: (size) =>
                  CustomPaint(size: size, painter: _RectIconPainter()),
            ),
            _buildButton(
              label: 'Logic',
              prototype: LogicBlock(''),
              shape: (size) =>
                  CustomPaint(size: size, painter: _DiamondIconPainter()),
            ),
            _buildButton(
              label: 'IO',
              prototype: IOBlock(''),
              shape: (size) =>
                  CustomPaint(size: size, painter: _ParallelogramIconPainter()),
            ),
            _buildButton(
              label: 'Subroutine',
              prototype: SubroutineBlock(''),
              shape: (size) =>
                  CustomPaint(size: size, painter: _SubroutineIconPainter()),
            ),
            _buildButton(
              label: 'For',
              prototype: ForBlock(''),
              shape: (size) =>
                  CustomPaint(size: size, painter: _HexagonIconPainter()),
            ),
            const Divider(),

            // Переключатель видимости сетки
            GestureDetector(
              onTap: () => onGridToggle(!isGridVisible),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: isGridVisible,
                      onChanged: (value) => onGridToggle(value ?? false),
                    ),
                    const SizedBox(width: 8),
                    const Text('Показать сетку'),
                  ],
                ),
              ),
            ),
            // Кнопка экспорта схемы в SVG
            ElevatedButton(
              onPressed: onExport,
              child: const Text('Экспорт в SVG'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: onExportJson,
              child: const Text('Экспорт в JSON'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: onLoad, child: const Text('Импорт')),

            // Кнопка вызова диалога задания размера блоков
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _showSetSizeDialog(context),
              child: const Text('Размер блоков'),
            ),

            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: onUndo,
              child: const Text('Отменить (Ctrl+Z)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: onRedo,
              child: const Text('Вернуть (Ctrl+Y)'),
            ),

            if (canSave) ...[
              const SizedBox(height: 8),
              // ElevatedButton(onPressed: onSave, child: const Text('Сохранить')),
              ElevatedButton(
                onPressed: isSaving ? null : onSave,
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Сохранить'),
              ),

              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: onClear,
                style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Очистить схему'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Показывает диалог для задания единого размера блоков
  void _showSetSizeDialog(BuildContext context) async {
    final widthController = TextEditingController(
      text: currentNodeSize.width.toStringAsFixed(0),
    );
    final heightController = TextEditingController(
      text: currentNodeSize.height.toStringAsFixed(0),
    );
    final result = await showDialog<Size?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Задать размер блоков'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widthController,
              decoration: const InputDecoration(labelText: 'Ширина'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: heightController,
              decoration: const InputDecoration(labelText: 'Высота'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(
                ctx,
                const Size(
                  NodeConstants.defaultWidth,
                  NodeConstants.defaultHeight,
                ),
              );
            },

            child: const Text('Сбросить'),
          ),

          TextButton(
            onPressed: () {
              final width = double.tryParse(widthController.text);
              final height = double.tryParse(heightController.text);
              if (width == null ||
                  height == null ||
                  width <= 0 ||
                  height <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Невалидные значения')),
                );
                return;
              }

              onSetNodeSize(Size(width, height));
            },
            child: const Text('Применить'),
          ),
        ],
      ),
    );
    if (result != null) {
      onSetNodeSize(result);
    }
  }

  // Строит кнопку выбора прототипа блока
  // Отображает мини-иконку фигуры и подпись
  Widget _buildButton({
    required String label,
    required GostNodeData prototype,
    required Widget Function(Size) shape,
  }) {
    final isSelected = selectedPrototype?.runtimeType == prototype.runtimeType;
    return ElevatedButton(
      onPressed: () => onSelectPrototype(isSelected ? null : prototype),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue.shade100 : null,
        minimumSize: const Size(160, 48),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(width: 28, height: 28, child: shape(const Size(28, 28))),
          const SizedBox(width: 12),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _RectIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DiamondIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(size.width / 2, size.height);
    path.lineTo(0, size.height / 2);
    path.close();
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ParallelogramIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    const skew = 6.0; // для размера 28x28
    path.moveTo(skew, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width - skew, size.height);
    path.lineTo(0, size.height);
    path.close();
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SubroutineIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, paint);
    const double left = 5.0;
    canvas.drawLine(Offset(left, 0), Offset(left, size.height), paint);
    final double right = size.width - 5.0;
    canvas.drawLine(Offset(right, 0), Offset(right, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HexagonIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final h2 = h / 2;
    final w4 = w / 4;
    final path = Path()
      ..moveTo(w4, 0)
      ..lineTo(w * 3 / 4, 0)
      ..lineTo(w, h2)
      ..lineTo(w * 3 / 4, h)
      ..lineTo(w4, h)
      ..lineTo(0, h2)
      ..close();
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
