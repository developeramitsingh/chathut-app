import 'package:flutter/material.dart';
import '../services/api_service.dart';

enum _HistoryRange { today, sevenDays, all }

class CallHistoryScreen extends StatefulWidget {
  final bool showEarnings;
  final bool nested;

  const CallHistoryScreen({
    super.key,
    this.showEarnings = false,
    this.nested = false,
  });

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _history = [];
  _HistoryRange _selectedRange = _HistoryRange.all;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rows = await ApiService.getCallHistory();
      if (!mounted) return;
      setState(() {
        _history = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    try {
      final date = DateTime.parse(value.toString()).toLocal();
      final dd = date.day.toString().padLeft(2, '0');
      final mm = date.month.toString().padLeft(2, '0');
      final hh = date.hour.toString().padLeft(2, '0');
      final min = date.minute.toString().padLeft(2, '0');
      return '$dd/$mm $hh:$min';
    } catch (_) {
      return value.toString();
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> get _filteredHistory {
    if (_selectedRange == _HistoryRange.all) {
      return _history;
    }

    final now = DateTime.now();
    return _history.where((row) {
      final endedAt = _parseDate(row['endedAt']);
      if (endedAt == null) return false;

      if (_selectedRange == _HistoryRange.today) {
        return endedAt.year == now.year &&
            endedAt.month == now.month &&
            endedAt.day == now.day;
      }

      final threshold = now.subtract(const Duration(days: 7));
      return endedAt.isAfter(threshold);
    }).toList();
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadHistory,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final historyRows = _filteredHistory;

    if (historyRows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Text(
            'No call history found for this range.',
            style: TextStyle(color: Colors.white54, fontSize: 15),
          ),
        ),
      );
    }

    final totalCalls = historyRows.length;
    final totalMinutes = historyRows.fold<int>(
      0,
      (sum, row) =>
          sum + (int.tryParse(row['durationMinutes']?.toString() ?? '0') ?? 0),
    );
    final totalCharged = historyRows.fold<int>(
      0,
      (sum, row) =>
          sum + (int.tryParse(row['chargedCoins']?.toString() ?? '0') ?? 0),
    );
    final totalEarned = historyRows.fold<int>(
      0,
      (sum, row) =>
          sum + (int.tryParse(row['earnedCoins']?.toString() ?? '0') ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Today'),
              selected: _selectedRange == _HistoryRange.today,
              onSelected: (_) {
                setState(() {
                  _selectedRange = _HistoryRange.today;
                });
              },
            ),
            ChoiceChip(
              label: const Text('7 Days'),
              selected: _selectedRange == _HistoryRange.sevenDays,
              onSelected: (_) {
                setState(() {
                  _selectedRange = _HistoryRange.sevenDays;
                });
              },
            ),
            ChoiceChip(
              label: const Text('All'),
              selected: _selectedRange == _HistoryRange.all,
              onSelected: (_) {
                setState(() {
                  _selectedRange = _HistoryRange.all;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161A40),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Calls: $totalCalls',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Minutes: $totalMinutes',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                widget.showEarnings
                    ? 'Earned: $totalEarned'
                    : 'Deducted: $totalCharged',
                style: TextStyle(
                  color: widget.showEarnings
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ListView.separated(
          itemCount: historyRows.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final row = historyRows[index];
            final name = row['counterpartyName']?.toString() ?? 'Unknown';
            final direction = row['direction']?.toString() ?? '';
            final minutes = int.tryParse(row['durationMinutes']?.toString() ?? '0') ?? 0;
            final charged = int.tryParse(row['chargedCoins']?.toString() ?? '0') ?? 0;
            final earned = int.tryParse(row['earnedCoins']?.toString() ?? '0') ?? 0;
            final endedAt = _formatDate(row['endedAt']);
            final amountText = widget.showEarnings
                ? 'Earned: $earned'
                : 'Charged: $charged';

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF14193E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF2E3368),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${direction == 'outgoing' ? 'Outgoing' : 'Incoming'} • $minutes min • $endedAt',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    amountText,
                    style: TextStyle(
                      color: widget.showEarnings
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = RefreshIndicator(
      onRefresh: _loadHistory,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: _buildContent(),
        ),
      ),
    );

    if (widget.nested) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Call History')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: content,
      ),
    );
  }
}
