import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../utils/dashboard_values.dart';

const _procurementBar = Color(0xFF5B9BD5);
const _targetLine = Color(0xFFED7D31);

class ProcurementValueChart extends StatefulWidget {
  const ProcurementValueChart({
    super.key,
    required this.buckets,
    required this.granularity,
    required this.onGranularityChanged,
    this.loading = false,
  });

  final List<ProcurementBucket> buckets;
  final String granularity;
  final ValueChanged<String> onGranularityChanged;
  final bool loading;

  @override
  State<ProcurementValueChart> createState() => _ProcurementValueChartState();
}

class _ProcurementValueChartState extends State<ProcurementValueChart> {
  int? _active;

  @override
  void didUpdateWidget(ProcurementValueChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buckets != widget.buckets ||
        oldWidget.granularity != widget.granularity) {
      _active = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final buckets = widget.buckets;
    final peak = buckets.fold<double>(
      0,
      (max, bucket) => math.max(
        max,
        math.max(rupeesToLakhs(bucket.ordered), rupeesToLakhs(bucket.received)),
      ),
    );
    final scale = buildChartYScale(peak);
    final active = _active != null && _active! < buckets.length
        ? buckets[_active!]
        : null;

    return _DashboardCard(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _CardTitle(
                  title: 'Procurement value',
                  color: _procurementBar,
                ),
              ),
              const SizedBox(width: 8),
              _GranularityPills(
                value: widget.granularity,
                enabled: !widget.loading,
                onChanged: widget.onGranularityChanged,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _LegendDot(color: _procurementBar, label: 'Procurement (₹L)'),
              _LegendDot(color: _targetLine, label: 'Target (received)'),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.loading)
            const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (buckets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'No procurement data for this period.',
                style: TextStyle(color: AppTheme.muted),
              ),
            )
          else ...[
            if (active != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.brandLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${active.label.isEmpty ? active.key : active.label}\n'
                  'Ordered ${formatFullInr(active.ordered)}'
                  '  ·  Received ${formatFullInr(active.received)}',
                  style: AppTheme.bodySmall.copyWith(height: 1.35),
                ),
              ),
            SizedBox(
              height: 196,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const axisWidth = 28.0;
                  final slot = buckets.length <= 1
                      ? constraints.maxWidth - axisWidth
                      : math.max(
                          36.0,
                          (constraints.maxWidth - axisWidth) / buckets.length,
                        );
                  final chartWidth = axisWidth + slot * buckets.length;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        final index = ((details.localPosition.dx - axisWidth) / slot)
                            .floor();
                        if (index < 0 || index >= buckets.length) return;
                        setState(() {
                          _active = _active == index ? null : index;
                        });
                      },
                      child: CustomPaint(
                        size: Size(math.max(chartWidth, constraints.maxWidth), 196),
                        painter: _ProcurementChartPainter(
                          buckets: buckets,
                          scale: scale,
                          active: _active,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProcurementChartPainter extends CustomPainter {
  _ProcurementChartPainter({
    required this.buckets,
    required this.scale,
    required this.active,
  });

  final List<ProcurementBucket> buckets;
  final ChartYScale scale;
  final int? active;

  @override
  void paint(Canvas canvas, Size size) {
    const axisWidth = 28.0;
    const bottom = 22.0;
    const top = 8.0;
    final plot = Rect.fromLTWH(
      axisWidth,
      top,
      size.width - axisWidth,
      size.height - bottom - top,
    );
    final grid = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 1;
    final labelStyle = AppTheme.bodySmall.copyWith(
      fontSize: 9,
      color: AppTheme.muted,
    );

    for (final tick in scale.ticks) {
      final y = _y(plot, tick);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _paintLabel(
        canvas,
        _tickLabel(tick),
        Offset(0, y - 6),
        labelStyle,
        maxWidth: axisWidth - 2,
      );
    }

    if (buckets.isEmpty) return;
    final slot = plot.width / buckets.length;
    final barWidth = math.min(slot * 0.42, 18.0);
    final barPaint = Paint()..color = _procurementBar;
    final activePaint = Paint()..color = const Color(0xFF3D7AB5);
    final points = <Offset>[];

    for (var i = 0; i < buckets.length; i++) {
      final bucket = buckets[i];
      final cx = plot.left + slot * i + slot / 2;
      final orderedH = scale.max <= 0
          ? 0.0
          : (rupeesToLakhs(bucket.ordered) / scale.max) * plot.height;
      final receivedY = _y(plot, rupeesToLakhs(bucket.received));
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barWidth / 2, plot.bottom - orderedH, barWidth, orderedH),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, i == active ? activePaint : barPaint);
      points.add(Offset(cx, receivedY));
      _paintLabel(
        canvas,
        bucket.label.isEmpty ? bucket.key : bucket.label,
        Offset(cx - slot / 2, plot.bottom + 4),
        labelStyle,
        maxWidth: slot - 2,
        alignCenter: true,
      );
    }

    if (points.length >= 2) {
      final line = Paint()
        ..color = _targetLine
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, line);
    }
    final dot = Paint()..color = _targetLine;
    for (final point in points) {
      canvas.drawCircle(point, 3, dot);
    }
  }

  double _y(Rect plot, double lakhs) {
    if (scale.max <= 0) return plot.bottom;
    return plot.bottom - (lakhs / scale.max) * plot.height;
  }

  String _tickLabel(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    required double maxWidth,
    bool alignCenter = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(8, maxWidth));
    final dx = alignCenter ? offset.dx + (maxWidth - painter.width) / 2 : offset.dx;
    painter.paint(canvas, Offset(dx, offset.dy));
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _ProcurementChartPainter oldDelegate) {
    return oldDelegate.buckets != buckets ||
        oldDelegate.scale.max != scale.max ||
        oldDelegate.active != active;
  }
}

class PurchasedMaterialsCard extends StatelessWidget {
  const PurchasedMaterialsCard({
    super.key,
    required this.title,
    required this.materials,
    required this.accent,
    this.loading = false,
  });

  final String title;
  final List<PurchasedMaterial> materials;
  final Color accent;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final maxValue = materials.fold<double>(
      0,
      (max, item) => math.max(max, item.displayValue),
    );
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(title: title, color: accent),
          const SizedBox(height: 8),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (materials.isEmpty)
            const Text(
              'No materials found for this period.',
              style: TextStyle(color: AppTheme.muted),
            )
          else
            for (var i = 0; i < materials.length; i++)
              _MaterialRow(
                rank: i + 1,
                material: materials[i],
                maxValue: maxValue,
                accent: accent,
              ),
        ],
      ),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.rank,
    required this.material,
    required this.maxValue,
    required this.accent,
  });

  final int rank;
  final PurchasedMaterial material;
  final double maxValue;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue <= 0
        ? 0.0
        : (material.displayValue / maxValue).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.muted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.titleSmall.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: fraction == 0 ? 0 : math.max(fraction, 0.04),
                    minHeight: 6,
                    backgroundColor: AppTheme.surface,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatCompactInr(material.displayValue),
            style: AppTheme.titleSmall.copyWith(color: accent, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class SitePurchaseCards extends StatelessWidget {
  const SitePurchaseCards({
    super.key,
    required this.sites,
    required this.selectedSiteId,
    required this.onSiteSelected,
  });

  final List<SitePrRow> sites;
  final String? selectedSiteId;
  final ValueChanged<SitePrRow> onSiteSelected;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            title: 'Site-wise purchase requests',
            color: AppTheme.brand,
          ),
          const SizedBox(height: 10),
          if (sites.isEmpty)
            const Text(
              'No sites for this view.',
              style: TextStyle(color: AppTheme.muted),
            )
          else
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sites.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final site = sites[index];
                  final selected =
                      selectedSiteId != null &&
                      selectedSiteId!.isNotEmpty &&
                      site.siteId == selectedSiteId;
                  final accent = AppTheme.colorAt(index);
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: site.siteId.isEmpty
                          ? null
                          : () => onSiteSelected(site),
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        width: 112,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: selected
                              ? accent.withValues(alpha: 0.08)
                              : Colors.white,
                          border: Border.all(
                            color: selected ? accent : AppTheme.border,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              site.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodySmall.copyWith(
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${site.prsRaised}',
                              style: AppTheme.titleMedium.copyWith(fontSize: 20),
                            ),
                            Text(
                              'PRs raised',
                              style: AppTheme.bodySmall.copyWith(
                                fontSize: 10,
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppTheme.gridGap),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.cardShadow,
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: AppTheme.titleMedium.copyWith(fontSize: 15)),
        ),
      ],
    );
  }
}

class _GranularityPills extends StatelessWidget {
  const _GranularityPills({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in const [
            ('day', 'Day'),
            ('week', 'Week'),
            ('month', 'Month'),
          ])
            _Pill(
              label: option.$2,
              selected: value == option.$1,
              onTap: enabled ? () => onChanged(option.$1) : null,
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.brand : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: AppTheme.titleSmall.copyWith(
              fontSize: 11,
              color: selected ? Colors.white : AppTheme.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTheme.bodySmall.copyWith(fontSize: 11)),
      ],
    );
  }
}
