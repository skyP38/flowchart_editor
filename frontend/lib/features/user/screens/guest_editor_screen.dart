import 'package:flutter/material.dart';

import '../../../core/storage/guest_diagram_storage.dart';
import '../../editor/screens/editor_screen.dart';
import '../../../core/navigation/last_route_storage.dart';

// Редактор без привязки к проекту - для неавторизованных пользователей
// Работает все кроме сохранения в БД
class GuestEditorScreen extends StatefulWidget {
  const GuestEditorScreen({super.key});

  @override
  State<GuestEditorScreen> createState() => _GuestEditorScreenState();
}

class _GuestEditorScreenState extends State<GuestEditorScreen> {
  int _resetKey = 0;

  Future<void> _clearDraft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Начать с нуля?'),
        content: const Text('Текущий черновик будет удалён.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await GuestDiagramStorage.instance.clear();
    if (!mounted) return;
    setState(() => _resetKey++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'На главную',
          onPressed: () => LastRouteStorage.instance.setGuest(false),
        ),
        title: const Text('Guest Editor'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Новая схема',
            onPressed: _clearDraft,
          ),
        ],
      ),
      body: EditorScreen(
        key: ValueKey(_resetKey),
        initialSnapshot: null,
        onSave: null,
        canSave: false,
      ),
    );
  }
}
