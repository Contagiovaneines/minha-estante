import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../library/domain/library_item.dart';
import '../../library/presentation/library_controller.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(libraryControllerProvider).value ?? [];
    final user = ref.watch(authControllerProvider).value;
    final sessions = user != null
        ? LocalStorageService.getReadingSessions(user.id)
        : <Map<String, dynamic>>[];
    final bookmarks = user != null
        ? LocalStorageService.getAllBookmarks(user.id)
        : <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Estatísticas',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: items.isEmpty
          ? _buildEmptyState(context)
          : _buildContent(context, items, sessions, bookmarks),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<LibraryItem> items,
    List<Map<String, dynamic>> sessions,
    List<Map<String, dynamic>> bookmarks,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryCards(items: items, sessions: sessions, bookmarks: bookmarks),
          const SizedBox(height: 28),
          _sectionTitle(context, 'Distribuição por tipo'),
          const SizedBox(height: 16),
          _TypeDonutChart(items: items),
          const SizedBox(height: 28),
          _sectionTitle(context, 'Status da leitura'),
          const SizedBox(height: 16),
          _StatusBarChart(items: items),
          const SizedBox(height: 28),
          _sectionTitle(context, 'Itens adicionados por semana'),
          const SizedBox(height: 16),
          _WeeklyLineChart(items: items),
          if (sessions.isNotEmpty) ...[
            const SizedBox(height: 28),
            _sectionTitle(context, 'Tempo de leitura (min/dia)'),
            const SizedBox(height: 16),
            _SessionBarChart(sessions: sessions),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) => Text(
    title,
    style: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );

  Widget _buildEmptyState(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bar_chart_rounded, size: 64, color: AppColors.border),
        const SizedBox(height: 16),
        Text(
          'Adicione livros à biblioteca\npara ver as estatísticas.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
      ],
    ),
  );
}

// ─── Summary Cards ────────────────────────────────────────────────────────────

class _SummaryCards extends StatelessWidget {
  final List<LibraryItem> items;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> bookmarks;

  const _SummaryCards({
    required this.items,
    required this.sessions,
    required this.bookmarks,
  });

  @override
  Widget build(BuildContext context) {
    final finished = items
        .where((e) => e.status == LibraryItemStatus.finished)
        .length;
    final reading = items
        .where((e) => e.status == LibraryItemStatus.reading)
        .length;
    final favorites = items.where((e) => e.isFavorite).length;
    final totalMinutes = sessions.fold<int>(
      0,
      (sum, s) => sum + ((s['durationSeconds'] as int? ?? 0) ~/ 60),
    );

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          label: 'Total',
          value: '${items.length}',
          icon: Icons.library_books_rounded,
          color: AppColors.primary,
        ),
        _StatCard(
          label: 'Lidos',
          value: '$finished',
          icon: Icons.check_circle_rounded,
          color: AppColors.localAccent,
        ),
        _StatCard(
          label: 'Lendo',
          value: '$reading',
          icon: Icons.auto_stories_rounded,
          color: AppColors.audioAccent,
        ),
        _StatCard(
          label: 'Favoritos',
          value: '$favorites',
          icon: Icons.favorite_rounded,
          color: Colors.pink,
        ),
        _StatCard(
          label: 'Marcadores',
          value: '${bookmarks.length}',
          icon: Icons.bookmark_rounded,
          color: AppColors.comicAccent,
        ),
        _StatCard(
          label: 'Min. lidos',
          value: '$totalMinutes',
          icon: Icons.timer_rounded,
          color: Colors.orange,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Donut Chart (by type) ────────────────────────────────────────────────────

class _TypeDonutChart extends StatefulWidget {
  final List<LibraryItem> items;
  const _TypeDonutChart({required this.items});

  @override
  State<_TypeDonutChart> createState() => _TypeDonutChartState();
}

class _TypeDonutChartState extends State<_TypeDonutChart> {
  int _touchedIndex = -1;

  static const _typeColors = {
    ItemType.pdf: AppColors.primary,
    ItemType.hq: AppColors.comicAccent,
    ItemType.audio: AppColors.audioAccent,
    ItemType.ebook: Colors.teal,
    ItemType.document: Colors.orange,
    ItemType.text: Colors.orange,
  };

  static const _typeLabels = {
    ItemType.pdf: 'PDF',
    ItemType.hq: 'HQ',
    ItemType.audio: 'Áudio',
    ItemType.ebook: 'Ebook',
    ItemType.document: 'Documento',
    ItemType.text: 'Texto',
  };

  @override
  Widget build(BuildContext context) {
    final counts = <ItemType, int>{};
    for (final item in widget.items) {
      counts[item.type] = (counts[item.type] ?? 0) + 1;
    }

    final entries = counts.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    final sections = entries.asMap().entries.map((entry) {
      final i = entry.key;
      final type = entry.value.key;
      final count = entry.value.value;
      final isTouched = i == _touchedIndex;
      return PieChartSectionData(
        value: count.toDouble(),
        color: _typeColors[type] ?? AppColors.border,
        radius: isTouched ? 72 : 58,
        title: isTouched ? '$count' : '',
        titleStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 44,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    setState(() {
                      _touchedIndex =
                          response?.touchedSection?.touchedSectionIndex ?? -1;
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: entries.map((e) {
              final color = _typeColors[e.key] ?? AppColors.border;
              final label = _typeLabels[e.key] ?? 'Outro';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$label (${e.value})',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Status Bar Chart ─────────────────────────────────────────────────────────

class _StatusBarChart extends StatelessWidget {
  final List<LibraryItem> items;
  const _StatusBarChart({required this.items});

  @override
  Widget build(BuildContext context) {
    final toRead = items
        .where((e) => e.status == LibraryItemStatus.toRead)
        .length;
    final reading = items
        .where((e) => e.status == LibraryItemStatus.reading)
        .length;
    final finished = items
        .where((e) => e.status == LibraryItemStatus.finished)
        .length;

    final data = [
      _BarEntry('Para ler', toRead, AppColors.border),
      _BarEntry('Lendo', reading, AppColors.audioAccent),
      _BarEntry('Lidos', finished, AppColors.localAccent),
    ].where((e) => e.value > 0).toList();

    if (data.isEmpty) return const SizedBox.shrink();

    final maxY = data
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            maxY: maxY + 1,
            barGroups: data.asMap().entries.map((e) {
              return BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: e.value.value.toDouble(),
                    color: e.value.color,
                    width: 32,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ],
              );
            }).toList(),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (val, meta) {
                    final i = val.toInt();
                    if (i < 0 || i >= data.length) return const SizedBox();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        data[i].label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (val, meta) => Text(
                    '${val.toInt()}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (val) => FlLine(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.2),
                strokeWidth: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarEntry {
  final String label;
  final int value;
  final Color color;
  const _BarEntry(this.label, this.value, this.color);
}

// ─── Weekly Line Chart ────────────────────────────────────────────────────────

class _WeeklyLineChart extends StatelessWidget {
  final List<LibraryItem> items;
  const _WeeklyLineChart({required this.items});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Group items added in the last 8 weeks
    final weekCounts = List.filled(8, 0);
    for (final item in items) {
      final diff = now.difference(item.createdAt).inDays;
      final week = diff ~/ 7;
      if (week < 8) weekCounts[7 - week]++;
    }

    final spots = weekCounts
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.toDouble()))
        .toList();

    final maxY = weekCounts.reduce((a, b) => a > b ? a : b).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: SizedBox(
        height: 160,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY < 1 ? 2 : maxY + 1,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: AppColors.primary,
                barWidth: 3,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
            ],
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (val, meta) {
                    final weeksAgo = 7 - val.toInt();
                    final label = weeksAgo == 0 ? 'Essa' : '-${weeksAgo}s';
                    return Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (val, meta) => Text(
                    '${val.toInt()}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (val) => FlLine(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.2),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}

// ─── Session Bar Chart (minutes per day) ─────────────────────────────────────

class _SessionBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  const _SessionBarChart({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dayTotals = <int, int>{};
    for (var i = 0; i < 7; i++) {
      dayTotals[i] = 0;
    }
    for (final s in sessions) {
      final date = DateTime.tryParse(s['date'] as String? ?? '');
      if (date == null) continue;
      final daysAgo = now.difference(date).inDays;
      if (daysAgo < 7) {
        dayTotals[daysAgo] =
            (dayTotals[daysAgo] ?? 0) +
            ((s['durationSeconds'] as int? ?? 0) ~/ 60);
      }
    }

    final bars = List.generate(7, (i) {
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: (dayTotals[6 - i] ?? 0).toDouble(),
            color: AppColors.audioAccent,
            width: 22,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      );
    });

    final maxY = dayTotals.values.reduce((a, b) => a > b ? a : b).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            maxY: maxY < 1 ? 5 : maxY + 2,
            barGroups: bars,
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (val, meta) {
                    final date = now.subtract(Duration(days: 6 - val.toInt()));
                    const days = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
                    return Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        days[date.weekday % 7],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (val, meta) => Text(
                    '${val.toInt()}m',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (val) => FlLine(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.2),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}
