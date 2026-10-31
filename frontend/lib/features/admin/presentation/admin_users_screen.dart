import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/last_route_storage.dart';
import '../../auth/domain/auth_repository.dart';
import '../data/admin_api.dart';
import '../models/admin_user.dart';
import '../../../core/network/api_error.dart';
import '../../../shared/widgets/user_chip.dart';

class AdminUsersScreen extends StatefulWidget {
  final VoidCallback onOpenEditor;
  final VoidCallback onOpenSessions;
  final VoidCallback onOpenLogs;
  const AdminUsersScreen({
    super.key,
    required this.onOpenEditor,
    required this.onOpenSessions,
    required this.onOpenLogs,
  });

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late final AdminApi _api;
  late Future<List<AdminUser>> _usersFuture;

  String _search = '';
  String _statusFilter = 'All statuses';

  @override
  void initState() {
    super.initState();
    _api = context.read<AdminApi>();
    _reload();
  }

  void _reload() {
    setState(() {
      _usersFuture = _api.listUsers();
    });
  }

  Future<void> _logout() async {
    await context.read<AuthRepository>().logout();
    await LastRouteStorage.instance.clear();
  }

  Future<void> _sessions() async {
    widget.onOpenSessions();
  }

  Future<void> _logs() async {
    widget.onOpenLogs();
  }

  Future<void> _showAddUserDialog() async {
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _AddUserDialog(),
    );

    if (values == null || !mounted) return;

    try {
      await _api.createUser(
        login: values['login']!,
        name: values['name']!,
        password: values['password']!,
        role: values['role']!,
      );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User created successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create user: $e')));
    }
  }

  List<AdminUser> _filterUsers(List<AdminUser> users) {
    final needle = _search.trim().toLowerCase();
    return users.where((user) {
      final matchesSearch =
          needle.isEmpty ||
          user.login.toLowerCase().contains(needle) ||
          user.name.toLowerCase().contains(needle) ||
          user.role.toLowerCase().contains(needle);

      final matchesStatus = switch (_statusFilter) {
        'Active' => user.isActive,
        'Inactive' => !user.isActive,
        _ => true,
      };

      return matchesSearch && matchesStatus;
    }).toList();
  }

  Future<void> _setUserActive(AdminUser user, bool active) async {
    if (!active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Block user?'),
          content: Text(
            'Block "${user.login}"? '
            'All their sessions will be terminated and they won\'t be able to log in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      await _api.setUserActive(user.id, active);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active
                ? 'User "${user.login}" unblocked'
                : 'User "${user.login}" blocked',
          ),
        ),
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      final msg = e.code == 'last_admin'
          ? 'You cannot block the last admin'
          : e.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update user: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 900;
    final narrow = width < 700;
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
        actions: compact
            ? [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: UserChip(compact: true),
                ),
                _buildMobileMenu(),
              ]
            : [
                _navButton('Flowchart editor', widget.onOpenEditor),
                _navButton('Users', _reload, active: true),
                _navButton('Sessions', _sessions),
                _navButton('Logs', _logs),
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
                      side: const BorderSide(
                        color: Color(0xFF767676),
                        width: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const UserChip(),
                const SizedBox(width: 12),
              ],
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          _buildPageHeader(narrow: narrow),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(narrow ? 16 : 40),
              child: FutureBuilder<List<AdminUser>>(
                future: _usersFuture,
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
                            child: const Text('Reload'),
                          ),
                        ],
                      ),
                    );
                  }

                  final users = _filterUsers(snapshot.data ?? []);
                  return narrow
                      ? _buildUserCards(users)
                      : _buildDesktopTable(users);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navButton(
    String label,
    VoidCallback? onPressed, {
    bool active = false,
  }) {
    return TextButton(
      onPressed: active ? null : onPressed,
      style: TextButton.styleFrom(
        backgroundColor: active ? const Color(0xFFF1EDFA) : Colors.transparent,
        foregroundColor: active
            ? const Color(0xFF6750A4)
            : const Color(0xFF1E1E1E),
        disabledForegroundColor: const Color(0xFF6750A4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildMobileMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Color(0xFF1E1E1E)),
      tooltip: 'Menu',
      onSelected: (value) {
        switch (value) {
          case 'editor':
            widget.onOpenEditor();
            break;
          case 'users':
            _reload();
            break;
          case 'sessions':
            _sessions();
            break;
          case 'logs':
            _logs();
            break;
          case 'logout':
            _logout();
            break;
        }
      },

      itemBuilder: (context) => [
        const PopupMenuItem(value: 'editor', child: Text('Flowchart editor')),
        PopupMenuItem(
          value: 'users',
          enabled: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1EDFA),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Users',
              style: TextStyle(
                color: Color(0xFF6750A4),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const PopupMenuItem(value: 'sessions', child: Text('Sessions')),
        const PopupMenuItem(value: 'logs', child: Text('Logs')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'logout', child: Text('Log out')),
      ],
    );
  }

  Widget _buildPageHeader({required bool narrow}) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: narrow ? 16 : 40,
        vertical: narrow ? 16 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Users',
                style: TextStyle(
                  fontSize: narrow ? 20 : 24,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E1E1E),
                ),
              ),
              FilledButton.icon(
                onPressed: _showAddUserDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add user'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6750A4),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          if (narrow) ...[
            _buildSearchField(),
            const SizedBox(height: 12),
            _buildStatusDropdown(fullWidth: true),
          ] else
            Row(
              children: [
                Expanded(child: _buildSearchField()),
                const SizedBox(width: 16),
                _buildStatusDropdown(fullWidth: false),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Search by login, name or role...',
          hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
          prefixIcon: const Icon(Icons.search, size: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFD9D9D9)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFD9D9D9)),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildStatusDropdown({required bool fullWidth}) {
    final dropdown = DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _statusFilter,
        isExpanded: fullWidth,
        items: [
          'All statuses',
          'Active',
          'Inactive',
        ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) => setState(() => _statusFilter = v!),
        style: const TextStyle(fontSize: 14, color: Color(0xFF1E1E1E)),
      ),
    );

    if (!fullWidth) return SizedBox(height: 40, child: dropdown);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD9D9D9)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: dropdown,
    );
  }

  //  Desktop version
  Widget _buildDesktopTable(List<AdminUser> users) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          _buildHeader(),
          if (users.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No users found')),
            )
          else
            for (int i = 0; i < users.length; i++)
              _buildRow(users[i], isLast: i == users.length - 1),
        ],
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
        login: const _HeaderCell('LOGIN'),
        name: const _HeaderCell('NAME'),
        role: const _HeaderCell('ROLE'),
        status: const _HeaderCell('STATUS'),
        created: const _HeaderCell('CREATED'),
        lastSeen: const _HeaderCell('LAST SEEN'),
        actions: const _HeaderCell('ACTIONS'),
      ),
    );
  }

  Widget _buildRow(AdminUser user, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: _columns(
        login: Text(
          user.login,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        name: Text(
          user.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
        ),
        role: _RoleBadge(role: user.role),
        status: _StatusBadge(isActive: user.isActive),
        created: Text(
          _formatDate(user.createdAt),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
        ),
        lastSeen: Text(
          user.lastLogin != null ? _formatDate(user.lastLogin!) : '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
        ),
        actions: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: user.isActive ? 'Block user' : 'Unblock user',
              onPressed: () => _setUserActive(user, !user.isActive),
              icon: Icon(
                user.isActive ? Icons.block : Icons.lock_open_outlined,
                color: user.isActive
                    ? const Color(0xFFB45309)
                    : const Color(0xFF059669),
              ),
            ),
            IconButton(
              tooltip: 'Delete user',
              onPressed: () => _confirmDeleteUser(user),
              icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _columns({
    required Widget login,
    required Widget name,
    required Widget role,
    required Widget status,
    required Widget created,
    required Widget lastSeen,
    Widget? actions,
  }) {
    return Row(
      children: [
        Expanded(flex: 2, child: login),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: name),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: role),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: status),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: created),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: lastSeen),
        if (actions != null) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Align(alignment: Alignment.centerRight, child: actions),
          ),
        ],
      ],
    );
  }

  //  Mobile version
  Widget _buildUserCards(List<AdminUser> users) {
    if (users.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('No users found')),
      );
    }

    return Column(children: [for (final user in users) _buildUserCard(user)]);
  }

  Widget _buildUserCard(AdminUser user) {
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
                  user.login,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              IconButton(
                tooltip: user.isActive ? 'Block user' : 'Unblock user',
                visualDensity: VisualDensity.compact,
                onPressed: () => _setUserActive(user, !user.isActive),
                icon: Icon(
                  user.isActive ? Icons.block : Icons.lock_open_outlined,
                  color: user.isActive
                      ? const Color(0xFFB45309)
                      : const Color(0xFF059669),
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: 'Delete user',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmDeleteUser(user),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFDC2626),
                  size: 20,
                ),
              ),
            ],
          ),
          if (user.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RoleBadge(role: user.role),
              _StatusBadge(isActive: user.isActive),
            ],
          ),
          const SizedBox(height: 10),
          _infoLine('Created', _formatDate(user.createdAt)),
          const SizedBox(height: 4),
          _infoLine(
            'Last seen',
            user.lastLogin != null ? _formatDate(user.lastLogin!) : '—',
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year.toString().substring(2)}';
  }

  Future<void> _confirmDeleteUser(AdminUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text('Are you sure you want to delete "${user.login}"? '),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.deleteUser(user.id);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('User "${user.login}" deleted')));
    } on ApiError catch (e) {
      if (!mounted) return;
      final message = e.code == 'last_admin'
          ? 'You cannot delete the last admin'
          : e.message;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete user'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF4B5563),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isAdmin ? const Color(0xFFFEF3C7) : const Color(0xFFE8F0FE),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isAdmin ? 'Admin' : 'User',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isAdmin ? const Color(0xFFB45309) : const Color(0xFF1A73E8),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isActive ? 'Active' : 'Blocked',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isActive ? const Color(0xFF059669) : const Color(0xFFEF4444),
        ),
      ),
    );
  }
}

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog();

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  String _role = 'user';

  @override
  void dispose() {
    _login.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, {
      'login': _login.text.trim(),
      'name': _name.text.trim(),
      'password': _password.text,
      'role': _role,
    });
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = MediaQuery.sizeOf(context).width < 460
        ? MediaQuery.sizeOf(context).width - 80
        : 380.0;

    return AlertDialog(
      title: const Text('Add user'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _login,
                  decoration: const InputDecoration(
                    labelText: 'Login',
                    hintText: '3–32 letters/digits/_',
                  ),
                  validator: (v) =>
                      RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Invalid login',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) =>
                      RegExp(
                        r'^(?=.*[A-Za-z])(?=.*[0-9]).{8,}$',
                      ).hasMatch(v ?? '')
                      ? null
                      : 'Min 8 chars, 1 letter, 1 digit',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('User')),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Administrator'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _role = v!),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6750A4),
          ),
          child: const Text('Create user'),
        ),
      ],
    );
  }
}
