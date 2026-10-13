import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/sidebar.dart';
import '../models/session.dart';
import '../../../core/network/api_service.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  static const double _createdWidth = 180;
  static const double _statusWidth = 150;
  static const double _activityWidth = 150;
  static const double _actionWidth = 180;
  static const double _colGap = 16;

  //final ApiService _api = ApiService();
  late final ApiService _api;
  late Future<List<Session>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _api = context.read<ApiService>();
    _sessionsFuture = _api.listSessions();
  }

  void _reload() {
    setState(() {
      _sessionsFuture = _api.listSessions();
    });
  }

  Future<void> _close(Session s) async {
    try {
      await _api.closeSession(s.id);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Row(
        children: [
          const Sidebar(currentRoute: 'session'),
          Expanded(
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(40),
                      child: FutureBuilder<List<Session>>(
                        future: _sessionsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Ошибка: ${snapshot.error}'),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _reload,
                                    child: const Text('Повторить'),
                                  ),
                                ],
                              ),
                            );
                          }
                          final sessions = snapshot.data ?? [];
                          return _buildContent(sessions);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFD9D9D9)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Session',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E1E1E),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF059669),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<Session> sessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active sessions',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E1E1E),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              _buildHeader(),
              if (sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No sessions')),
                )
              else
                for (int i = 0; i < sessions.length; i++)
                  _buildRow(
                    sessions[i],
                    isLast: i == sessions.length - 1,
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: _columns(
        session: const _HeaderCell('SESSION'),
        created: const _HeaderCell('CREATED'),
        status: const _HeaderCell('STATUS'),
        activity: const _HeaderCell('ACTIVITY'),
        action: const _HeaderCell('ACTION', align: TextAlign.center),
      ),
    );
  }

  Widget _buildRow(Session s, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFF3F4F6)),
              ),
      ),
      child: _columns(
        session: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.laptop_mac,
                size: 16,
                color: Color(0xFF4B5563),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Session #${s.id}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
        created: Text(
          s.createdLabel,
          style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
        ),
        status: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: s.isActive
                ? const Color(0xFFECFDF5)
                : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            s.statusLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: s.isActive
                  ? const Color(0xFF059669)
                  : const Color(0xFFEF4444),
            ),
          ),
        ),
        activity: Text(
          s.activityLabel,
          style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
        ),
        action: Align(
          alignment: Alignment.centerRight,
          child: s.isActive
              ? _TerminateButton(onPressed: () => _close(s))
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _columns({
    required Widget session,
    required Widget created,
    required Widget status,
    required Widget activity,
    required Widget action,
  }) {
    return Row(
      children: [
        Expanded(child: session),
        const SizedBox(width: _colGap),
        SizedBox(width: _createdWidth, child: created),
        const SizedBox(width: _colGap),
        SizedBox(width: _statusWidth, child: status),
        const SizedBox(width: _colGap),
        SizedBox(width: _activityWidth, child: activity),
        const SizedBox(width: _colGap),
        SizedBox(width: _actionWidth, child: action),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final TextAlign align;
  const _HeaderCell(this.text, {this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF4B5563),
      ),
    );
  }
}

class _TerminateButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _TerminateButton({this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          border: Border.all(color: const Color(0xFFFEE2E2)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'End the session',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFFEF4444),
          ),
        ),
      ),
    );
  }
}
