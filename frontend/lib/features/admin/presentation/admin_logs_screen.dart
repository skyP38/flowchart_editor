import 'dart:math' as math;
import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/last_route_storage.dart';
import '../../auth/domain/auth_repository.dart';
import '../data/admin_api.dart';
import '../models/admin_log.dart';
import '../../user/widgets/user.dart';

class AdminLogsScreen extends StatefulWidget {
  final VoidCallback onOpenUsers;
  final VoidCallback onOpenEditor;
  final VoidCallback onOpenSessions;

  const AdminLogsScreen({
    super.key,
    required this.onOpenUsers,
    required this.onOpenEditor,
    required this.onOpenSessions,
  });

  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends State<AdminLogsScreen> {
  static const _pageSize = 10;

  late final AdminApi _api;
  late Future<AdminLogPage> _logsFuture;

  final _offset = 0;
  final Set<int> _expandedIds = {};

  bool _showFilters = false;

  bool _isExporting = false;

  DateTime? _selectedDate;
  String? _selectedUser;
  String? _selectedEvent;
  String? _selectedObject;
  String? _selectedStatus;

  bool get _hasActiveFilters =>
      _selectedDate != null ||
      _selectedUser != null ||
      _selectedEvent != null ||
      _selectedObject != null ||
      _selectedStatus != null;

  void _resetFilters() {
    setState(() {
      _selectedDate = null;
      _selectedUser = null;
      _selectedEvent = null;
      _selectedObject = null;
      _selectedStatus = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _api = context.read<AdminApi>();
    _logsFuture = _api.listLogs(limit: _pageSize, offset: 0);
  }

  void _reload() {
    setState(() {
      _logsFuture = _api.listLogs(limit: _pageSize, offset: _offset);
    });
  }

  Future<void> _logout() async {
    await context.read<AuthRepository>().logout();

    if (!mounted) return;

    await LastRouteStorage.instance.clear();
  }

  @override
  void dispose() {
    super.dispose();
  }

  bool get _isNarrow => MediaQuery.sizeOf(context).width < 700;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
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
                _navButton('Users', widget.onOpenUsers),
                _navButton('Sessions', widget.onOpenSessions),
                _navButton('Logs', _reload, active: true), // ← текущий
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildPageHeader(),
            Expanded(
              child: FutureBuilder<AdminLogPage>(
                future: _logsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Color(0xFFEF4444),
                            size: 32,
                          ),
                          const SizedBox(height: 12),
                          const Text('Could not load logs'),
                          const SizedBox(height: 12),
                          Text(
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _reload,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  final page =
                      snapshot.data ??
                      const AdminLogPage(
                        logs: [],
                        total: 0,
                        limit: _pageSize,
                        offset: 0,
                      );
                  return Column(
                    children: [
                      if (_showFilters) _buildFilterPanel(page.logs),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(_isNarrow ? 12 : 40),
                          child: _isNarrow
                              ? _buildCards(page)
                              : _buildTable(page),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
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

  Widget _buildCards(AdminLogPage page) {
    final filteredLogs = _filterLogs(page.logs);

    if (filteredLogs.isEmpty) {
      return Center(
        child: Text(
          page.logs.isEmpty
              ? 'No log entries found'
              : 'No logs match the selected filters',
          style: const TextStyle(color: Color(0xFF4B5563)),
        ),
      );
    }

    return ListView.separated(
      itemCount: filteredLogs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildLogCard(filteredLogs[index]),
    );
  }

  Widget _buildLogCard(AdminLog entry) {
    final expanded = _expandedIds.contains(entry.id);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            if (expanded) {
              _expandedIds.remove(entry.id);
            } else {
              _expandedIds.add(entry.id);
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
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
                      entry.action,
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
                  _statusBadge(entry.status),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: const Color(0xFF6B7280),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _logInfoRow(Icons.person_outline, entry.login),
              const SizedBox(height: 6),
              _logInfoRow(Icons.category_outlined, entry.objectLabel),
              const SizedBox(height: 6),
              _logInfoRow(Icons.schedule, _formatDateOneLine(entry.createdAt)),
              if (expanded) ...[
                const Divider(height: 24),
                _logDetailRow('ID', '#${entry.id}'),
                const SizedBox(height: 6),
                _logDetailRow('Time', _formatDateFull(entry.createdAt)),
                const SizedBox(height: 6),
                _logDetailRow('User', entry.login),
                const SizedBox(height: 6),
                _logDetailRow('Event', entry.action),
                const SizedBox(height: 6),
                _logDetailRow('Object', entry.objectLabel),
                const SizedBox(height: 6),
                _logDetailRow('Status', entry.status),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _logInfoRow(IconData icon, String text) {
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

  Widget _logDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
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

  String _formatDateOneLine(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String _formatDateFull(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)}:${two(date.second)} · '
        '${two(date.day)}.${two(date.month)}.${date.year}';
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
            widget.onOpenUsers();
            break;
          case 'sessions':
            widget.onOpenSessions();
            break;
          case 'logs':
            _reload();
            break;
          case 'logout':
            _logout();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'editor', child: Text('Flowchart editor')),
        const PopupMenuItem(value: 'users', child: Text('Users')),
        const PopupMenuItem(value: 'sessions', child: Text('Sessions')),
        PopupMenuItem(
          value: 'logs',
          enabled: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1EDFA),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Logs',
              style: TextStyle(
                color: Color(0xFF6750A4),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'logout', child: Text('Log out')),
      ],
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
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Logs',
                  style: TextStyle(
                    fontSize: compact ? 24 : 28,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),

              // Экспорт
              if (_isExporting)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    final hasFilters =
                        _selectedDate != null ||
                        _selectedUser != null ||
                        _selectedEvent != null ||
                        _selectedObject != null ||
                        _selectedStatus != null;

                    return PopupMenuButton<String>(
                      tooltip: 'Export CSV',
                      icon: const Icon(
                        Icons.download_outlined,
                        size: 22,
                        color: Color(0xFF1E1E1E),
                      ),
                      onSelected: (value) {
                        if (value == 'filtered') _exportCsv(onlyFiltered: true);
                        if (value == 'all') _exportCsv(onlyFiltered: false);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'filtered',
                          enabled: hasFilters,
                          child: const Text('Export filtered'),
                        ),
                        const PopupMenuItem(
                          value: 'all',
                          child: Text('Export all'),
                        ),
                      ],
                    );
                  },
                ),

              const SizedBox(width: 8),

              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _showFilters = !_showFilters;
                  });
                },
                icon: _hasActiveFilters
                    ? const Icon(Icons.filter_alt, size: 18)
                    : const Icon(Icons.filter_alt_outlined, size: 18),
                label: Text(
                  _hasActiveFilters
                      ? (_showFilters ? 'Hide filters' : 'Filters (active)')
                      : (_showFilters ? 'Hide filters' : 'Filters'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterPanel(List<AdminLog> logs) {
    List<String> getOptions(String Function(AdminLog) selector) {
      final options = logs
          .map((entry) => selector(entry).trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();

      options.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      return options;
    }

    Widget dropdownFilter({
      required String label,
      required String? value,
      required List<String> options,
      required ValueChanged<String?> onChanged,
    }) {
      final selectedValue = options.contains(value) ? value : null;

      return SizedBox(
        width: 180,
        child: DropdownButtonFormField<String>(
          initialValue: selectedValue,
          isExpanded: true,
          hint: const Text('All'),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: selectedValue == null
                ? null
                : IconButton(
                    tooltip: 'Clear $label',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => onChanged(null),
                  ),
          ),
          items: options.map((option) {
            return DropdownMenuItem<String>(
              value: option,
              child: Text(option, maxLines: 1, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      );
    }

    Widget dateFilter() {
      return SizedBox(
        width: 180,
        child: InkWell(
          onTap: () async {
            final now = DateTime.now();

            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate ?? now,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              initialEntryMode: DatePickerEntryMode.calendarOnly,
            );

            if (picked != null) {
              setState(() {
                _selectedDate = DateTime(picked.year, picked.month, picked.day);
              });
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Date',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _selectedDate == null
                  ? const Icon(Icons.calendar_month, size: 18)
                  : IconButton(
                      tooltip: 'Clear date',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          _selectedDate = null;
                        });
                      },
                    ),
            ),
            child: Text(
              _selectedDate == null ? 'All dates' : _formatDate(_selectedDate!),
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          dateFilter(),
          dropdownFilter(
            label: 'User',
            value: _selectedUser,
            options: getOptions((entry) => entry.login),
            onChanged: (value) {
              setState(() => _selectedUser = value);
            },
          ),
          dropdownFilter(
            label: 'Event',
            value: _selectedEvent,
            options: getOptions((entry) => entry.action),
            onChanged: (value) {
              setState(() => _selectedEvent = value);
            },
          ),
          dropdownFilter(
            label: 'Object',
            value: _selectedObject,
            options: getOptions((entry) => entry.objectLabel),
            onChanged: (value) {
              setState(() => _selectedObject = value);
            },
          ),
          dropdownFilter(
            label: 'Status',
            value: _selectedStatus,
            options: getOptions((entry) => entry.status),
            onChanged: (value) {
              setState(() => _selectedStatus = value);
            },
          ),
          TextButton.icon(
            onPressed: _hasActiveFilters ? _resetFilters : null,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('Reset filters'),
          ),
        ],
      ),
    );
  }

  /// Подтягивает все логи с бэка, проходя страницы по 100, пока
  /// не заберет total или пока страница не окажется пустой.
  Future<List<AdminLog>> _fetchAllLogs() async {
    const pageSize = 100;
    const safetyCap = 100000; // защита от бесконечного цикла при баге бэка

    final all = <AdminLog>[];
    var offset = 0;

    while (offset < safetyCap) {
      final page = await _api.listLogs(limit: pageSize, offset: offset);
      if (page.logs.isEmpty) break;
      all.addAll(page.logs);
      if (all.length >= page.total) break;
      offset += pageSize;
    }
    return all;
  }

  Future<void> _exportCsv({required bool onlyFiltered}) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      // При filtered - тянем все и фильтруем локально.
      // Иначе экспорт ограничился бы только текущей страницей.
      final logs = onlyFiltered
          ? _filterLogs(await _fetchAllLogs())
          : await _fetchAllLogs();

      if (logs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Nothing to export')));
        return;
      }

      final csv = _buildCsv(logs);
      final stamp = _csvTimestamp(DateTime.now());
      final name = 'logs_${onlyFiltered ? 'filtered_' : 'all_'}$stamp';

      await FileSaver.instance.saveFile(
        name: name,
        bytes: utf8.encode(csv),
        ext: 'csv',
        mimeType: MimeType.other,
        customMimeType: 'text/csv',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${logs.length} log(s) to $name.csv')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not export CSV: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _buildCsv(List<AdminLog> logs) {
    final sb = StringBuffer('\uFEFF');
    sb.writeln('ID,Time,User,Event,Object,Status,Details');

    for (final e in logs) {
      sb.writeln(
        [
          e.id.toString(),
          _csvCell(_formatDateTimeCsv(e.createdAt)),
          _csvCell(e.login),
          _csvCell(e.action),
          _csvCell(e.objectLabel),
          _csvCell(e.status),
          _csvCell(e.details),
        ].join(','),
      );
    }
    return sb.toString();
  }

  String _csvCell(String raw) {
    final needsQuotes =
        raw.contains(',') ||
        raw.contains('"') ||
        raw.contains('\n') ||
        raw.contains('\r');
    if (!needsQuotes) return raw;
    return '"${raw.replaceAll('"', '""')}"';
  }

  String _formatDateTimeCsv(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  String _csvTimestamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}_'
        '${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }

  List<AdminLog> _filterLogs(List<AdminLog> logs) {
    bool matchesSelection(String value, String? selected) {
      return selected == null || value.toLowerCase() == selected.toLowerCase();
    }

    return logs
        .where((entry) {
          final date = entry.createdAt;

          final matchesDate =
              _selectedDate == null ||
              (date.year == _selectedDate!.year &&
                  date.month == _selectedDate!.month &&
                  date.day == _selectedDate!.day);

          return matchesDate &&
              matchesSelection(entry.login, _selectedUser) &&
              matchesSelection(entry.action, _selectedEvent) &&
              matchesSelection(entry.objectLabel, _selectedObject) &&
              matchesSelection(entry.status, _selectedStatus);
        })
        .toList(growable: false);
  }

  Widget _buildTable(AdminLogPage page) {
    final filteredLogs = _filterLogs(page.logs);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(constraints.maxWidth, 900.0);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            height: constraints.maxHeight,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _buildTableHeader(),
                  Expanded(
                    child: filteredLogs.isEmpty
                        ? Center(
                            child: Text(
                              page.logs.isEmpty
                                  ? 'No log entries found'
                                  : 'No logs match the selectes filters',
                              style: TextStyle(color: Color(0xFF4B5563)),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredLogs.length,
                            itemBuilder: (context, index) {
                              return _buildLogRow(filteredLogs[index]);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          Expanded(flex: 2, child: _headerCell('TIME')),
          Expanded(flex: 2, child: _headerCell('USER')),
          Expanded(flex: 3, child: _headerCell('EVENT')),
          Expanded(flex: 3, child: _headerCell('OBJECT')),
          Expanded(flex: 2, child: _headerCell('STATUS')),
        ],
      ),
    );
  }

  Widget _buildLogRow(AdminLog entry) {
    final expanded = _expandedIds.contains(entry.id);

    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (expanded) {
                _expandedIds.remove(entry.id);
              } else {
                _expandedIds.add(entry.id);
              }
            });
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _bodyCell(
                    _formatDate(entry.createdAt),
                    color: const Color(0xFF4B5563),
                    twoLines: true,
                  ),
                ),
                Expanded(flex: 2, child: _bodyCell(entry.login, bold: true)),
                Expanded(flex: 3, child: _bodyCell(entry.action)),
                Expanded(flex: 3, child: _bodyCell(entry.objectLabel)),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _statusBadge(entry.status),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (expanded)
          Container(
            width: double.infinity,
            color: const Color(0xFFF9FAFB),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _logDetailRow('ID', '#${entry.id}'),
                const SizedBox(height: 6),
                _logDetailRow('Time', _formatDateFull(entry.createdAt)),
                const SizedBox(height: 6),
                _logDetailRow('User', entry.login),
                const SizedBox(height: 6),
                _logDetailRow('Event', entry.action),
                const SizedBox(height: 6),
                _logDetailRow('Object', entry.objectLabel),
                const SizedBox(height: 6),
                _logDetailRow('Status', entry.status),
              ],
            ),
          ),
      ],
    );
  }

  Widget _headerCell(String label) {
    return SizedBox(
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          color: Color(0xFF4B5563),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _bodyCell(
    String value, {
    bool bold = false,
    bool twoLines = false,
    Color color = const Color(0xFF111827),
  }) {
    return SizedBox(
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Text(
          value,
          maxLines: twoLines ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final success = status.toLowerCase() == 'success';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFE6F4EA) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: success ? const Color(0xFF137333) : const Color(0xFFEF4444),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(date.hour)}:${two(date.minute)}\n'
        '${two(date.day)}.${two(date.month)}.${date.year}';
  }
}
