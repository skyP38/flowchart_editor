import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_service.dart';
import '../../editor/screens/editor_screen.dart';
import '../../editor/persistence/editor_state.dart';

class FlowchartEditorPage extends StatefulWidget {
  final int projectId;
  final int flowchartId;
  const FlowchartEditorPage({
    super.key,
    required this.projectId,
    required this.flowchartId,
  });

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
    debugPrint(
      '[EditorPage] init pid=${widget.projectId} fid=${widget.flowchartId}',
    );
    _api = context.read<ApiService>();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await _api.getFlowchartContent(
        widget.projectId,
        widget.flowchartId,
      );

      final isEmpty =
          json.isEmpty ||
          json['nodes'] == null ||
          (json['nodes'] as List).isEmpty;
      setState(() {
        _initial = isEmpty ? null : EditorSnapshot.fromJson(json);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save(EditorSnapshot snapshot, String previewSvg) async {
    final content = snapshot.toJson();

    content['previewSvg'] = previewSvg;

    debugPrint('Saving SVG length: ${previewSvg.length}');
    await _api.updateFlowchartContent(
      widget.projectId,
      widget.flowchartId,
      content,
    );

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
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }
    return EditorScreen(
      initialSnapshot: _initial,
      onSave: _save,
      onBack: () => Navigator.of(context).pop(),
    );
  }
}
