import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as Math;

import '../models/session.dart';
import '../../auth/data/api/auth_api.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final AuthApi _api;
  late Future<List<Session>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _api = context.read<AuthApi>();
    _sessionsFuture = _api.sessions();
  }

  void _reload() {
    setState(() {
      _sessionsFuture = _api.sessions();
    });
  }

  Future<void> _close(Session s) async {
    try {
      await _api.revokeSession(s.id);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  bool get _isNarrow => MediaQuery.sizeOf(context).width < 700;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // _buildTopBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(_isNarrow ? 12 : 40),
            child: FutureBuilder<List<Session>>(
              future: _sessionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Error: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _reload,
                          child: const Text('Repeat'),
                        ),
                      ],
                    ),
                  );
                }
                final sessions = snapshot.data ?? [];
                return _isNarrow
                    ? _buildCardsContent(sessions)
                    : _buildTableContent(sessions);
              },
            ),
          ),
        ),
      ],
    );
  }

  // Mobile version
  Widget _buildCardsContent(List<Session> sessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active sessions',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E1E1E),
          ),
        ),
        const SizedBox(height: 16),
        if (sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No sessions')),
          )
        else
          for (final s in sessions) _buildSessionCard(s),
      ],
    );
  }

  Widget _buildSessionCard(Session s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Session #${s.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: s.isActive
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  s.statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: s.isActive
                        ? const Color(0xFF059669)
                        : const Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(Icons.devices_outlined, s.deviceName),
          const SizedBox(height: 6),
          _infoRow(Icons.location_on_outlined, s.location),
          const SizedBox(height: 6),
          _infoRow(Icons.schedule, s.createdLabel),
          const SizedBox(height: 6),
          _infoRow(Icons.access_time, s.activityLabel),
          if (s.isActive) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: _TerminateButton(onPressed: () => _close(s)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6B7280)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
          ),
        ),
      ],
    );
  }

  //  Desktop version
  Widget _buildTableContent(List<Session> sessions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = Math.max(constraints.maxWidth, 800.0);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: _columns(
        session: const _HeaderCell('SESSION', align: TextAlign.left),
        device: const _HeaderCell('DEVICE', align: TextAlign.center),
        location: const _HeaderCell('LOCATION', align: TextAlign.center),
        created: const _HeaderCell('CREATED', align: TextAlign.center),
        status: const _HeaderCell('STATUS', align: TextAlign.center),
        activity: const _HeaderCell('ACTIVITY', align: TextAlign.center),
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
            : const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: _columns(
        session: Row(
          children: [
            Expanded(
              child: Text(
                'Session #${s.id}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
        device: Row(
          children: [
            Expanded(
              child: Text(
                s.deviceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              ),
            ),
          ],
        ),
        location: Text(
          s.location,
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        ),
        created: Text(
          s.createdLabel,
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
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
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
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
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
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
    required Widget device,
    required Widget location,
    required Widget created,
    required Widget status,
    required Widget activity,
    required Widget action,
  }) {
    return Row(
      children: [
        Expanded(flex: 3, child: session),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: device),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: location),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: created),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: status),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: activity),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: action),
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
