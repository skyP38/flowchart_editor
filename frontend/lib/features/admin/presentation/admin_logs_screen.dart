import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/last_route_storage.dart';
import '../../auth/domain/auth_repository.dart';
import '../data/admin_api.dart';
import '../models/admin_log.dart';

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

  DateTime? _selectedDate;
  String? _selectedUser;
  String? _selectedEvent;
  String? _selectedObject;
  String? _selectedStatus;

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
            onPressed: widget.onOpenSessions,
            label: const Text(
              'Sessions',
              style: TextStyle(color: Color(0xFF1E1E1E)),
            ),
          ),
          TextButton.icon(
            onPressed: _reload,
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
                          padding: EdgeInsets.all(
                            MediaQuery.sizeOf(context).width < 600 ? 16 : 40,
                          ),
                          child: _buildTable(page),
                        ),
                      ),
                    ],
                  );
                },
              ),
              //),
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
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _showFilters = !_showFilters;
                  });
                },
                label: Text(_showFilters ? 'Hide filters' : 'Filters'),
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
        ],
      ),
    );
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
        final tableWidth = math.max(constraints.maxWidth, 1120.0);

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
          _headerCell('TIME', 146),
          _headerCell('USER', 177),
          _headerCell('EVENT', 180),
          _headerCell('OBJECT', 180),
          _headerCell('STATUS', 92),
        ],
      ),
    );
  }

  Widget _buildLogRow(AdminLog entry) {
    final expanded = _expandedIds.contains(entry.id);

    return Column(
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              _bodyCell(
                _formatDate(entry.createdAt),
                146,
                color: const Color(0xFF4B5563),
                twoLines: true,
              ),
              _bodyCell(entry.login, 177, bold: true),
              _bodyCell(entry.action, 180),
              _bodyCell(entry.objectLabel, 180),
              SizedBox(
                width: 92,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _statusBadge(entry.status),
                ),
              ),
            ],
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            color: const Color(0xFFF9FAFB),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
      ],
    );
  }

  Widget _headerCell(String label, double width) {
    return SizedBox(
      width: width,
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
    String value,
    double width, {
    bool bold = false,
    bool twoLines = false,
    Color color = const Color(0xFF111827),
  }) {
    return SizedBox(
      width: width,
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
