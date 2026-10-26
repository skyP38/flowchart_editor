import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/last_route_storage.dart';
import '../../auth/domain/auth_repository.dart';
import '../data/admin_api.dart';
import '../models/admin_session.dart';

class AdminSessionsScreen extends StatefulWidget {
  final VoidCallback onOpenUsers;
  final VoidCallback onOpenEditor;
  final VoidCallback onOpenLogs;

  const AdminSessionsScreen({
    super.key,
    required this.onOpenUsers,
    required this.onOpenEditor,
    required this.onOpenLogs,
  });

  @override
  State<AdminSessionsScreen> createState() => _AdminSessionsScreenState();
}

class _AdminSessionsScreenState extends State<AdminSessionsScreen> {
  late final AdminApi _api;
  late Future<List<AdminSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _api = context.read<AdminApi>();
    _reload();
  }

  void _reload() {
    setState(() {
      _sessionsFuture = _api.listSessions();
    });
  }

  Future<void> _logout() async {
    await context.read<AuthRepository>().logout();
    await LastRouteStorage.instance.clear();
  }

  Future<void> _terminate(AdminSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End session?'),
        content: Text('End the session for ${session.login}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _api.revokeSession(session.id);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Session ended')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not end session: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF6750A4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.schema, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            const Text('FlowChart Editor'),
          ],
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E1E1E),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const Border(
          bottom: BorderSide(color: Color(0xFFD9D9D9), width: 1),
        ),
        actions: [
          TextButton.icon(
            onPressed: widget.onOpenEditor,
            label: const Text(
              'Flowchart editor',
              style: TextStyle(color: Color(0xFF1E1E1E)),
            ),
          ),
          TextButton.icon(
            onPressed: widget.onOpenUsers,
            label: const Text(
              'Users',
              style: TextStyle(color: Color(0xFF1E1E1E)),
            ),
          ),
          TextButton.icon(
            onPressed: _reload,
            label: const Text(
              'Sessions',
              style: TextStyle(color: Color(0xFF1E1E1E)),
            ),
          ),
          TextButton.icon(
            onPressed: widget.onOpenLogs,
            label: const Text(
              'Logs',
              style: TextStyle(color: Color(0xFF1E1E1E)),
            ),
          ),
          TextButton.icon(
            onPressed: _logout,
            label: const Text(
              'Log out',
              style: TextStyle(color: Color(0xFF1E1E1E)),
            ),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFE3E3E3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFF767676), width: 1),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildPageHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: _buildSessionCard(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 40,
            vertical: compact ? 18 : 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: const Text(
            'Sessions',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<List<AdminSession>>(
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
                  Text('Could not load sessions: ${snapshot.error}'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _reload,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final sessions = snapshot.data ?? const <AdminSession>[];
          return Column(
            children: [
              _buildHeader(),
              Expanded(
                child: sessions.isEmpty
                    ? const Center(child: Text('No sessions found'))
                    : ListView.builder(
                        itemCount: sessions.length,
                        itemBuilder: (context, index) => _sessionRow(
                          sessions[index],
                          isLast: index == sessions.length - 1,
                        ),
                      ),
              ),
              Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
                ),
                child: Row(
                  children: [
                    Text(
                      '${sessions.length} session${sessions.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh sessions',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
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
        name: const _HeaderCell('NAME'),
        device: const _HeaderCell('DEVICE'),
        location: const _HeaderCell('LOCATION'),
        status: const _HeaderCell('STATUS'),
        created: const _HeaderCell('CREATED'),
        actions: const _HeaderCell('ACTIONS', align: TextAlign.right),
      ),
    );
  }

  Widget _sessionRow(AdminSession session, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: _columns(
        name: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.login.isEmpty ? 'User #${session.userId}' : session.login,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            if (session.name.isNotEmpty)
              Text(
                session.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
          ],
        ),
        device: Row(
          children: [
            /*Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.devices_outlined,
                size: 16,
                color: Color(0xFF4B5563),
              ),
            ),
            const SizedBox(width: 12),*/
            Expanded(
              child: Text(
                session.deviceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: Color(0xFF111827)),
              ),
            ),
          ],
        ),
        location: Text(
          session.location,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        ),
        status: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: session.active
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              session.statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: session.active
                    ? const Color(0xFF059669)
                    : const Color(0xFFEF4444),
              ),
            ),
          ),
        ),
        created: Text(
          session.createdLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
        ),
        actions: Align(
          alignment: Alignment.centerRight,
          child: session.active
              ? TextButton(
                  onPressed: () => _terminate(session),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    backgroundColor: const Color(0xFFFEF2F2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: const BorderSide(color: Color(0xFFFEE2E2)),
                    ),
                  ),
                  child: const Text(
                    'End session',
                    maxLines: 1,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                )
              : const Text('—', style: TextStyle(color: Color(0xFF6B7280))),
        ),
      ),
    );
  }

  Widget _columns({
    required Widget name,
    required Widget device,
    required Widget location,
    required Widget status,
    required Widget created,
    required Widget actions,
  }) {
    return Row(
      children: [
        Expanded(flex: 3, child: name),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: device),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: location),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: status),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: created),
        const SizedBox(width: 12),
        SizedBox(width: 120, child: actions),
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
      maxLines: 1,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF4B5563),
        letterSpacing: .3,
      ),
    );
  }
}
