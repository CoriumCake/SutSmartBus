import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/bus.dart';
import '../providers/data_provider.dart';

class _HourlyLoadStat {
  final int hour;
  final double averageCount;
  final int samples;

  const _HourlyLoadStat({
    required this.hour,
    required this.averageCount,
    required this.samples,
  });
}

class _PassengerDayViewModel {
  final List<_HourlyLoadStat> hours;
  final bool isPlaceholder;
  final int totalSamples;

  const _PassengerDayViewModel({
    required this.hours,
    required this.isPlaceholder,
    required this.totalSamples,
  });

  _HourlyLoadStat get busiestHour =>
      hours.reduce((a, b) => a.averageCount >= b.averageCount ? a : b);
}

enum _StatsMode {
  day,
  average,
}

class PassengerStatsScreen extends ConsumerStatefulWidget {
  const PassengerStatsScreen({super.key});

  @override
  ConsumerState<PassengerStatsScreen> createState() =>
      _PassengerStatsScreenState();
}

class _PassengerStatsScreenState extends ConsumerState<PassengerStatsScreen> {
  static const int _seatCapacity = 33;
  static const int _maxLookbackDays = 14;

  DateTime _selectedDate = DateTime.now();
  String _selectedBusMac = 'all';
  int? _selectedHour;
  _StatsMode _mode = _StatsMode.day;
  int _selectedAverageWindowDays = 7;
  bool _loading = true;
  late _PassengerDayViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = _buildPlaceholderModel();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() => _loading = true);

    final api = ref.read(apiServiceProvider);
    final now = DateTime.now();
    final hoursBack = _mode == _StatsMode.day
        ? () {
            final selectedDay = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
            );
            final selectedDayEnd = selectedDay.add(const Duration(days: 1));
            return math.max(
              24,
              now.difference(selectedDayEnd).inHours + 24,
            );
          }()
        : _selectedAverageWindowDays * 24;

    final history = await api.fetchPassengerCountHistory(
      hours: math.min(hoursBack, _maxLookbackDays * 24),
    );

    if (!mounted) return;

    setState(() {
      _viewModel = _mode == _StatsMode.day
          ? _buildFromDayHistory(history)
          : _buildFromAverageHistory(history);
      _selectedHour = null;
      _loading = false;
    });
  }

  _PassengerDayViewModel _buildFromDayHistory(
      List<Map<String, dynamic>> history) {
    final selectedDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final nextDay = selectedDay.add(const Duration(days: 1));

    final buckets = <int, List<double>>{
      for (int hour = 6; hour <= 20; hour++) hour: <double>[],
    };

    for (final row in history) {
      final count = (row['count'] as num?)?.toDouble();
      final timestampRaw = row['timestamp']?.toString();
      final busMac = row['bus_mac']?.toString();
      final timestamp = timestampRaw == null
          ? null
          : DateTime.tryParse(timestampRaw)?.toLocal();

      if (count == null || timestamp == null) continue;
      if (_selectedBusMac != 'all' && busMac != _selectedBusMac) continue;
      if (timestamp.isBefore(selectedDay) || !timestamp.isBefore(nextDay)) {
        continue;
      }
      if (!buckets.containsKey(timestamp.hour)) continue;

      buckets[timestamp.hour]!.add(count);
    }

    final stats = buckets.entries.map((entry) {
      final values = entry.value;
      final average =
          values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;
      return _HourlyLoadStat(
        hour: entry.key,
        averageCount: average,
        samples: values.length,
      );
    }).toList();

    final totalSamples = stats.fold<int>(0, (sum, stat) => sum + stat.samples);

    if (totalSamples == 0) {
      return _buildPlaceholderModel();
    }

    return _PassengerDayViewModel(
      hours: stats,
      isPlaceholder: false,
      totalSamples: totalSamples,
    );
  }

  _PassengerDayViewModel _buildFromAverageHistory(
    List<Map<String, dynamic>> history,
  ) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: _selectedAverageWindowDays));

    final buckets = <int, List<double>>{
      for (int hour = 6; hour <= 20; hour++) hour: <double>[],
    };

    for (final row in history) {
      final count = (row['count'] as num?)?.toDouble();
      final timestampRaw = row['timestamp']?.toString();
      final busMac = row['bus_mac']?.toString();
      final timestamp = timestampRaw == null
          ? null
          : DateTime.tryParse(timestampRaw)?.toLocal();

      if (count == null || timestamp == null) continue;
      if (_selectedBusMac != 'all' && busMac != _selectedBusMac) continue;
      if (timestamp.isBefore(cutoff) || timestamp.isAfter(now)) continue;
      if (!buckets.containsKey(timestamp.hour)) continue;

      buckets[timestamp.hour]!.add(count);
    }

    final stats = buckets.entries.map((entry) {
      final values = entry.value;
      final average =
          values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;
      return _HourlyLoadStat(
        hour: entry.key,
        averageCount: average,
        samples: values.length,
      );
    }).toList();

    final totalSamples = stats.fold<int>(0, (sum, stat) => sum + stat.samples);

    if (totalSamples == 0) {
      return _buildPlaceholderModel();
    }

    return _PassengerDayViewModel(
      hours: stats,
      isPlaceholder: false,
      totalSamples: totalSamples,
    );
  }

  _PassengerDayViewModel _buildPlaceholderModel() {
    final weekday = _selectedDate.weekday;
    final template = _mode == _StatsMode.average
        ? const [3, 6, 9, 11, 10, 9, 10, 12, 15, 19, 21, 18, 13, 9, 6]
        : switch (weekday) {
            DateTime.monday => [
                4,
                8,
                12,
                15,
                11,
                9,
                10,
                13,
                18,
                22,
                24,
                21,
                16,
                11,
                7
              ],
            DateTime.friday => [
                3,
                7,
                10,
                13,
                10,
                8,
                9,
                12,
                16,
                20,
                23,
                19,
                14,
                9,
                6
              ],
            _ => [2, 5, 8, 11, 9, 7, 8, 10, 14, 18, 20, 17, 12, 8, 5],
          };

    final stats = List.generate(15, (index) {
      final hour = 6 + index;
      return _HourlyLoadStat(
        hour: hour,
        averageCount: template[index].toDouble(),
        samples: 0,
      );
    });

    return _PassengerDayViewModel(
      hours: stats,
      isPlaceholder: true,
      totalSamples: 0,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: now.subtract(const Duration(days: _maxLookbackDays)),
      lastDate: now,
    );

    if (picked == null) return;

    setState(() => _selectedDate = picked);
    await _fetchStats();
  }

  String _hourLabel(int hour) {
    return '${hour.toString().padLeft(2, '0')}:00';
  }

  String _busiestSummary(_HourlyLoadStat stat) {
    final nextHour = stat.hour + 1;
    return '${_hourLabel(stat.hour)}-${_hourLabel(nextHour)}';
  }

  String _selectedBusLabel(List<Bus> buses) {
    if (_selectedBusMac == 'all') return 'All buses';
    Bus? bus;
    for (final item in buses) {
      if (item.busMac == _selectedBusMac) {
        bus = item;
        break;
      }
    }
    return bus?.busName ?? _selectedBusMac;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buses = ref.watch(busesProvider);
    final dateText = DateFormat('EEE, d MMM yyyy').format(_selectedDate);
    final highestValue = math.max(
      1.0,
      _viewModel.hours.map((item) => item.averageCount).reduce(math.max),
    );
    final busiest = _viewModel.busiestHour;
    _HourlyLoadStat? selectedStat;
    if (_selectedHour != null) {
      for (final stat in _viewModel.hours) {
        if (stat.hour == _selectedHour) {
          selectedStat = stat;
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crowd Stats'),
        actions: [
          IconButton(
            onPressed: _fetchStats,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchStats,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              _mode == _StatsMode.day
                  ? 'Passenger trend by day'
                  : 'Average passenger trend',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<_StatsMode>(
              segments: const [
                ButtonSegment<_StatsMode>(
                  value: _StatsMode.day,
                  label: Text('Day'),
                ),
                ButtonSegment<_StatsMode>(
                  value: _StatsMode.average,
                  label: Text('Average'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) async {
                final next = selection.first;
                if (next == _mode) return;
                setState(() => _mode = next);
                await _fetchStats();
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (_mode == _StatsMode.day)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickDate,
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              dateText,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_mode == _StatsMode.average)
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [7, 14].map((days) {
                        return ChoiceChip(
                          label: Text('${days}D'),
                          selected: _selectedAverageWindowDays == days,
                          onSelected: (_) async {
                            if (_selectedAverageWindowDays == days) return;
                            setState(() => _selectedAverageWindowDays = days);
                            await _fetchStats();
                          },
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedBusMac,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All buses'),
                      ),
                      ...buses.map(
                        (bus) => DropdownMenuItem(
                          value: bus.busMac,
                          child: Text(
                            bus.busName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      setState(() => _selectedBusMac = value);
                      await _fetchStats();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedBusLabel(buses),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildMiniStat(
                          theme,
                          label: 'Peak',
                          value: _busiestSummary(busiest),
                        ),
                        const SizedBox(width: 8),
                        _buildMiniStat(
                          theme,
                          label: _mode == _StatsMode.day ? 'Load' : 'Avg',
                          value: '${busiest.averageCount.round()} pax',
                          highlighted: true,
                        ),
                        if (_viewModel.isPlaceholder) ...[
                          const SizedBox(width: 8),
                          _buildMiniStat(
                            theme,
                            label: 'Mode',
                            value: 'Preview',
                          ),
                        ],
                      ],
                    ),
                    if (selectedStat != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bar_chart_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_hourLabel(selectedStat.hour)}  •  ${selectedStat.averageCount.round()} pax',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 260,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: _viewModel.hours.map((stat) {
                          final isPeak = stat.hour == busiest.hour;
                          final isSelected = stat.hour == _selectedHour;
                          return Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  setState(() {
                                    _selectedHour = _selectedHour == stat.hour
                                        ? null
                                        : stat.hour;
                                  });
                                },
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 180),
                                          width: double.infinity,
                                          height: (stat.averageCount /
                                                  highestValue) *
                                              170,
                                          decoration: BoxDecoration(
                                            color: isSelected || isPeak
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.primary
                                                    .withValues(alpha: 0.18),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _hourLabel(stat.hour).substring(0, 2),
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: isSelected
                                            ? theme.colorScheme.primary
                                            : null,
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _viewModel.isPlaceholder
                    ? 'Preview data'
                    : _mode == _StatsMode.day
                        ? '${_viewModel.totalSamples} samples'
                        : '${_viewModel.totalSamples} samples • ${_selectedAverageWindowDays} day average',
                style: theme.textTheme.labelMedium,
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(
    ThemeData theme, {
    required String label,
    required String value,
    bool highlighted = false,
  }) {
    final bg = highlighted
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHighest;
    final fg =
        highlighted ? theme.colorScheme.primary : theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
