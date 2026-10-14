import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_service.dart';
import '../../editor/screens/editor_screen.dart';
import '../../editor/persistence/editor_state.dart';

class FlowchartEditorPage extends StatefulWidget {
  final int flowchartId;
  const FlowchartEditorPage({super.key, required this.flowchartId});

  @override
  State<FlowchartEditorPage> createState() => _FlowchartEditorPageState();
}

class _FlowchartEditorPageState extends State<FlowchartEditorPage> {
  late final ApiService _api;
  EditorSnapshot? _initial;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = context.read<ApiService>();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await _api.getFlowchartContent(widget.flowchartId);
      setState(() {
        _initial = EditorSnapshot.fromJson(json);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save(EditorSnapshot snapshot) async {
    await _api.updateFlowchartContent(widget.flowchartId, snapshot.toJson());
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Схема сохранена')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Ошибка: $_error')));
    }
    return EditorScreen(initialSnapshot: _initial, onSave: _save);
  }
}
