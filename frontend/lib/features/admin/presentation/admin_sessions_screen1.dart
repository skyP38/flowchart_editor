import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/last_route_storage.dart';
import '../../auth/domain/auth_repository.dart';
import '../data/admin_api.dart';
import '../models/admin_session.dart';

class AdminSessionsScreen extends StatefulWidget {
  final VoidCallback onOpenUsers;
  final VoidCallback onOpenEditor;

  const AdminSessionsScreen({
    super.key,
    required this.onOpenUsers,
    required this.onOpenEditor,
  });

  @override
  State<AdminSessionsScreen> createState() => _AdminSessionsScreenState();
}

class _AdminSessionsScreenState extends State<AdminSessionsScreen> {
  static const _ink = Color(0xFF1E1E1E);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);
  static const _purple = Color(0xFF6750A4);

  late final AdminApi _api;
  late Future<List<AdminSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _api = context.read<AdminApi>();
    _sessionsFuture = _api.listSessions();
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
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session ended')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not end session: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildNavigationHeader(),
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

  Widget _buildNavigationHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final actions = Wrap(
          alignment: compact ? WrapAlignment.start : WrapAlignment.end,
          spacing: 4,
          runSpacing: 6,
          children: [
            _navigationButton('Flowchart editor', widget.onOpenEditor),
            _navigationButton('Users', widget.onOpenUsers),
            _navigationButton('Sessions', _reload, active: true),
            _navigationButton('Logs', null),
            _navigationButton('Log out', _logout, logout: true),
          ],
        );

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 32,
            vertical: compact ? 12 : 0,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFD9D9D9)),
            ),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _brand(),
                    const SizedBox(height: 10),
                    actions,
                  ],
                )
              : SizedBox(
                  height: 96,
                  child: Row(
                    children: [
                      _brand(),
                      const Spacer(),
                      actions,
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _brand() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _purple,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.schema,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'FlowChart Editor',
          style: TextStyle(
            fontSize: 18,
            //fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
      ],
    );
  }

  Widget _navigationButton(
    String label,
    VoidCallback? onPressed, {
    bool active = false,
    bool logout = false,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: _ink,
        backgroundColor: logout
            ? const Color(0xFFE3E3E3)
            : active
                ? const Color(0xFFF3F4F6)
                : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: logout
              ? const BorderSide(color: Color(0xFF767676))
              : BorderSide.none,
        ),
      ),
      child: Text(label),
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
            border: Border(
              bottom: BorderSide(color: _border),
            ),
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
        border: Border.all(color: _border),
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
                      style: const TextStyle(fontSize: 13, color: _muted),
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
        border: Border(bottom: BorderSide(color: _border)),
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
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
          ],
        ),
        device: Row(
          children: [
            Container(
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
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Unknown device',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: Color(0xFF111827)),
              ),
            ),
          ],
        ),
        location: const Text(
          'Not recorded',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, color: _muted),
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
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : const Text('—', style: TextStyle(color: _muted)),
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
/*import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/last_route_storage.dart';
import '../../auth/domain/auth_repository.dart';
import '../data/admin_api.dart';
import '../models/admin_session.dart';

class AdminSessionsScreen extends StatefulWidget {
  final VoidCallback onOpenUsers;
  final VoidCallback onOpenEditor;

  const AdminSessionsScreen({
    super.key,
    required this.onOpenUsers,
    required this.onOpenEditor,
  });

  @override
  State<AdminSessionsScreen> createState() => _AdminSessionsScreenState();
}

class _AdminSessionsScreenState extends State<AdminSessionsScreen> {
  static const _ink = Color(0xFF1E1E1E);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);
  static const _purple = Color(0xFF6750A4);

  late final AdminApi _api;
  late Future<List<AdminSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _api = context.read<AdminApi>();
    _sessionsFuture = _api.listSessions();
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
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session ended')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not end session: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildNavigationHeader(),
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

  Widget _buildNavigationHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final actions = Wrap(
          alignment: compact ? WrapAlignment.start : WrapAlignment.end,
          spacing: 4,
          runSpacing: 6,
          children: [
            _navigationButton('Flowchart editor', widget.onOpenEditor),
            _navigationButton('Users', widget.onOpenUsers),
            _navigationButton('Sessions', _reload, active: true),
            _navigationButton('Logs', null),
            _navigationButton('Log out', _logout, logout: true),
          ],
        );

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 32,
            vertical: compact ? 12 : 0,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFD9D9D9)),
            ),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _brand(),
                    const SizedBox(height: 10),
                    actions,
                  ],
                )
              : SizedBox(
                  height: 96,
                  child: Row(
                    children: [
                      _brand(),
                      const Spacer(),
                      actions,
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _brand() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _purple,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.account_tree_outlined,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'FlowChart Editor',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
      ],
    );
  }

  Widget _navigationButton(
    String label,
    VoidCallback? onPressed, {
    bool active = false,
    bool logout = false,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: _ink,
        backgroundColor: logout
            ? const Color(0xFFE3E3E3)
            : active
                ? const Color(0xFFF3F4F6)
                : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: logout
              ? const BorderSide(color: Color(0xFF767676))
              : BorderSide.none,
        ),
      ),
      child: Text(label),
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
            border: Border(
              bottom: BorderSide(color: _border),
            ),
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
        border: Border.all(color: _border),
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
              _tableHeader(),
              Expanded(
                child: sessions.isEmpty
                    ? const Center(child: Text('No sessions found'))
                    : ListView.builder(
                        itemCount: sessions.length,
                        itemBuilder: (context, index) => _sessionRow(
                          sessions[index],
                          shaded: index.isOdd,
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
                      style: const TextStyle(fontSize: 13, color: _muted),
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

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1040,
          child: Row(
            children: [
              _headerCell('NAME', 180),
              _headerCell('DEVICE', 220),
              _headerCell('LOCATION', 180),
              _headerCell('STATUS', 180),
              _headerCell('CREATED', 140),
              _headerCell('ACTIONS', 140),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sessionRow(AdminSession session, {required bool shaded}) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: shaded ? const Color(0xFFF9FAFB) : Colors.white,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF3F4F6)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1040,
          child: Row(
            children: [
              SizedBox(
                width: 180,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
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
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: Row(
                  children: [
                    Container(
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
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Unknown device',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: Color(0xFF111827)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width: 180,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Not recorded',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: _muted),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
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
                ),
              ),
              SizedBox(
                width: 140,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    session.createdLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: session.active
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => _terminate(session),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              backgroundColor: const Color(0xFFFEF2F2),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                          ),
                        )
                      : const Text('—', style: TextStyle(color: _muted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String label, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF4B5563),
            letterSpacing: .3,
          ),
        ),
      ),
    );
  }
}*/
