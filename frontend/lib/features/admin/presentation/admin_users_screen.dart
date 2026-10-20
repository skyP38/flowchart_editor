import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/last_route_storage.dart';
import '../../auth/domain/auth_repository.dart';
import '../data/admin_api.dart';
import '../models/admin_user.dart';

class AdminUsersScreen extends StatefulWidget {
  final VoidCallback onOpenEditor;
  const AdminUsersScreen({super.key, required this.onOpenEditor});

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
    //TODO
  }

  Future<void> _logs() async {
    //TODO
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create user: $e')),
      );
    }
  }

  List<AdminUser> _filterUsers(List<AdminUser> users) {
    final needle = _search.trim().toLowerCase();
    return users.where((user) {
      final matchesSearch = needle.isEmpty ||
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
              child: const Icon(
                Icons.schema,
                color: Colors.white,
                size: 18,
              ),
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
        elevation: 1,
        actions: [
          TextButton.icon(
            onPressed: widget.onOpenEditor,
            label: const Text('Flowchart editor',
              style: TextStyle(color: const Color(0xFF1E1E1E)),
            ),
          ),
          TextButton.icon(
            onPressed: _reload,
            label: const Text('Users',
              style: TextStyle(color: const Color(0xFF1E1E1E)),
            ),
          ),
          TextButton.icon(
            onPressed: _sessions,
            label: const Text('Sessions',
              style: TextStyle(color: const Color(0xFF1E1E1E)),
            ),
          ),
          TextButton.icon(
            onPressed: _logs,
            label: const Text('Logs',
              style: TextStyle(color: const Color(0xFF1E1E1E)),
            ),
          ),
          TextButton.icon(
            onPressed: _logout,
            label: const Text('Log out',
              style: TextStyle(color: const Color(0xFF1E1E1E)),
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
        ],
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Admin users',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1E1E1E)),
                    ),
                    FilledButton.icon(
                      onPressed: _showAddUserDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add user'),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6750A4)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          onChanged: (v) => setState(() => _search = v),
                          decoration: InputDecoration(
                            hintText: 'Search by login, name or role...',
                            hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                            prefixIcon: const Icon(Icons.search, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFD9D9D9))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFD9D9D9))),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      height: 40,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _statusFilter,
                          items: ['All statuses', 'Active', 'Inactive']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setState(() => _statusFilter = v!),
                          style: const TextStyle(fontSize: 14, color: Color(0xFF1E1E1E)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
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
                          ElevatedButton(onPressed: _reload, child: const Text('Reload')),
                        ],
                      ),
                    );
                  }

                  final users = _filterUsers(snapshot.data ?? []);
                  return _buildTable(users);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
 
  Widget _buildTable(List<AdminUser> users) {
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
      ),
    );
  }

  Widget _buildRow(AdminUser user, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: _columns(
        login: Text(
          user.login,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
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
      ],
    );
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year.toString().substring(2)}';
  }

  Future<void> _showUserDetails(AdminUser user) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user.name.isEmpty ? user.login : user.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Login: ${user.login}'),
            Text('Role: ${user.role}'),
            Text('Status: ${user.isActive ? "Active" : "Inactive"}'),
            Text('Created: ${_formatDate(user.createdAt)}'),
            Text('Last seen: ${user.lastLogin == null ? "—" : _formatDate(user.lastLogin!)}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
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
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4B5563)),
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
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
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
    return AlertDialog(
      title: const Text('Add user'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _login,
                decoration: const InputDecoration(labelText: 'Login', hintText: '3–32 letters/digits/_'),
                validator: (v) => RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(v?.trim() ?? '') ? null : 'Invalid login',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) => RegExp(r'^(?=.*[A-Za-z])(?=.*[0-9]).{8,}$').hasMatch(v ?? '') ? null : 'Min 8 chars, 1 letter, 1 digit',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('User')),
                  DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                ],
                onChanged: (v) => setState(() => _role = v!),
              ),
            ],
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
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6750A4)),
          child: const Text('Create user'),
        ),
      ],
    );
  }
}
