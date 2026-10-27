import 'package:flutter/material.dart';

import '../../core/session.dart';
import 'report_logic.dart';

/// Tarih aralığı seçimi (hazır aralıklar + özel)
class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.preset, required this.range, required this.onChanged});

  final RangePreset preset;
  final DateRange range;
  final void Function(RangePreset preset, DateRange range) onChanged;

  @override
  Widget build(BuildContext context) {
    final today = session.ctx.today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              for (final p in RangePreset.values) ...[
                ChoiceChip(
                  label: Text(p.label),
                  selected: preset == p,
                  onSelected: (_) async {
                    if (p != RangePreset.custom) {
                      onChanged(p, rangeFor(p, today));
                      return;
                    }
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(today.year - 3),
                      lastDate: today,
                      initialDateRange: DateTimeRange(start: range.from, end: range.to),
                    );
                    if (picked != null) onChanged(p, (from: picked.start, to: picked.end));
                  },
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(rangeLabel(range), style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

Color percentColor(double? p) {
  if (p == null) return Colors.grey;
  if (p >= 85) return const Color(0xFF2E7D32);
  if (p >= 70) return const Color(0xFF7CB342);
  if (p >= 50) return const Color(0xFFEF6C00);
  return const Color(0xFFC62828);
}

/// Yüzde çubuğu + etiket
class PercentBar extends StatelessWidget {
  const PercentBar({super.key, required this.percent, this.height = 8});

  final double? percent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = percentColor(percent);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: percent == null ? 0 : (percent! / 100).clamp(0, 1),
        minHeight: height,
        color: color,
        backgroundColor: color.withValues(alpha: 0.15),
      ),
    );
  }
}

/// Büyük yuvarlak genel başarı göstergesi
class ScoreCircle extends StatelessWidget {
  const ScoreCircle({super.key, required this.percent, this.size = 56});

  final double? percent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = percentColor(percent);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: percent == null ? 0 : (percent! / 100).clamp(0, 1),
            strokeWidth: size / 10,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
          Center(
            child: Text(
              formatPercent(percent),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: size / 4.2, color: percent == null ? Colors.grey : null),
            ),
          ),
        ],
      ),
    );
  }
}
