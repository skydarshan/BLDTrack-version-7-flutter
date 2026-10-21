import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/dashboard_values.dart';

const _blue = PdfColor.fromInt(0x5B9BD5);
const _orange = PdfColor.fromInt(0xED7D31);
const _green = PdfColor.fromInt(0x198754);
const _red = PdfColor.fromInt(0xDC3545);

/// Full procurement dashboard: summary, site list, chart, and material tables.
Future<Uint8List> buildDashboardPdfBytes({
  required DashboardOverview overview,
  List<SitePrRow>? siteRows,
  required ProcurementOverview procurement,
  required String chartGranularity,
  required String siteLabel,
  required String dateFrom,
  required String dateTo,
  DateTime? generatedAt,
}) async {
  final when = generatedAt ?? DateTime.now();
  final sites = siteRows ?? overview.sites;
  final granularityLabel = switch (chartGranularity) {
    'day' => 'Day',
    'month' => 'Month',
    _ => 'Week',
  };
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Text(
          'Dashboard Overview',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          "Here's what's happening across all your sites",
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),
        _keyValues([
          ['Site filter', siteLabel.isEmpty ? 'All sites' : siteLabel],
          ['From', formatDisplayDate(dateFrom)],
          ['To', formatDisplayDate(dateTo)],
          ['Generated', formatGeneratedAt(when)],
        ]),
        _section('Summary'),
        _keyValues([
          [
            'Remaining inventory value',
            formatPdfCompactInr(overview.inventoryValue),
          ],
          [
            'Inventory trend',
            overview.trendPercent == null
                ? '-'
                : '${overview.trendPercent}%',
          ],
          ['Active sites', '${overview.activeSites}'],
          ['Sites status', overview.sitesStatus],
          [
            'Items yet to be received',
            formatPdfCompactInr(overview.yetToReceive),
          ],
          ['Pending line items', '${overview.pendingLines}'],
          ['Total purchase requests', '${overview.prCount}'],
          [
            'PR trend',
            overview.prTrend == null ? '-' : '+${overview.prTrend}',
          ],
          ['PR pending', '${overview.prPending}'],
        ]),
        _section('Site-wise purchase requests'),
        if (sites.isEmpty)
          _empty('No site data for the selected filters.')
        else
          _table(
            headers: const ['Site', 'PRs Raised'],
            rows: [
              for (final site in sites) [site.siteName, '${site.prsRaised}'],
            ],
            numericFrom: 1,
          ),
        _section('Procurement Value ($granularityLabel)'),
        if (procurement.buckets.isEmpty)
          _empty('No procurement data for this period.')
        else ...[
          _procurementChart(procurement.buckets),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              _swatch(_blue),
              pw.SizedBox(width: 4),
              pw.Text('Procurement (Rs. L)', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(width: 12),
              _swatch(_orange),
              pw.SizedBox(width: 4),
              pw.Text('Target (received)', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.SizedBox(height: 8),
          _table(
            headers: const ['Period', 'Ordered (Rs.)', 'Received (Rs.)'],
            rows: [
              for (final bucket in procurement.buckets)
                [
                  bucket.label.isEmpty ? bucket.key : bucket.label,
                  formatPdfInr(bucket.ordered),
                  formatPdfInr(bucket.received),
                ],
            ],
            numericFrom: 1,
          ),
        ],
        _section('Top 10 Purchased Materials'),
        _materialsBlock(procurement.top, _green),
        _section('Least 10 Purchased Materials'),
        _materialsBlock(procurement.least, _red),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _section(String title) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Divider(color: PdfColors.grey300, thickness: 0.4),
      ],
    ),
  );
}

pw.Widget _empty(String message) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(
      message,
      style: pw.TextStyle(
        fontSize: 9,
        fontStyle: pw.FontStyle.italic,
        color: PdfColors.grey700,
      ),
    ),
  );
}

pw.Widget _keyValues(List<List<String>> rows) {
  return pw.Column(
    children: [
      for (final row in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 150,
                child: pw.Text(
                  '${row[0]}:',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  sanitizePdfText(row[1].isEmpty ? '-' : row[1]),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

pw.Widget _table({
  required List<String> headers,
  required List<List<String>> rows,
  required int numericFrom,
}) {
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: [
      for (final row in rows) [for (final cell in row) sanitizePdfText(cell)],
    ],
    headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 8),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellAlignments: {
      for (var i = numericFrom; i < headers.length; i++) i: pw.Alignment.centerRight,
    },
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    border: null,
  );
}

pw.Widget _swatch(PdfColor color) {
  return pw.Container(width: 10, height: 6, color: color);
}

pw.Widget _procurementChart(List<ProcurementBucket> buckets) {
  final peak = buckets.fold<double>(
    0,
    (max, bucket) => math.max(
      max,
      math.max(rupeesToLakhs(bucket.ordered), rupeesToLakhs(bucket.received)),
    ),
  );
  final scale = buildChartYScale(peak);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('Rs. L', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
      pw.SizedBox(height: 2),
      pw.SizedBox(
        height: 110,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            for (final bucket in buckets)
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 1),
                  child: _bucketColumn(bucket, scale),
                ),
              ),
          ],
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Row(
        children: [
          for (final bucket in buckets)
            pw.Expanded(
              child: pw.Text(
                sanitizePdfText(
                  bucket.label.isEmpty ? bucket.key : bucket.label,
                ),
                textAlign: pw.TextAlign.center,
                maxLines: 1,
                style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
              ),
            ),
        ],
      ),
    ],
  );
}

pw.Widget _bucketColumn(ProcurementBucket bucket, ChartYScale scale) {
  final orderedH = scale.max <= 0
      ? 0.0
      : (rupeesToLakhs(bucket.ordered) / scale.max) * 96;
  final receivedH = scale.max <= 0
      ? 0.0
      : (rupeesToLakhs(bucket.received) / scale.max) * 96;
  return pw.SizedBox(
    height: 100,
    child: pw.Stack(
      alignment: pw.Alignment.bottomCenter,
      children: [
        pw.Container(
          width: 10,
          height: math.max(orderedH, 0.5),
          color: _blue,
        ),
        pw.Positioned(
          bottom: receivedH,
          child: pw.Container(
            width: 6,
            height: 6,
            decoration: const pw.BoxDecoration(
              color: _orange,
              shape: pw.BoxShape.circle,
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _materialsBlock(List<PurchasedMaterial> materials, PdfColor accent) {
  if (materials.isEmpty) return _empty('No materials found for this period.');
  final items = materials.take(10).toList();
  final maxValue = items.fold<double>(
    0,
    (max, item) => math.max(max, item.orderedValue),
  );
  return pw.Column(
    children: [
      for (var i = 0; i < items.length; i++)
        _materialLine(i + 1, items[i], maxValue, accent),
      pw.SizedBox(height: 6),
      _table(
        headers: const ['#', 'Item', 'Ordered (Rs.)'],
        rows: [
          for (var i = 0; i < items.length; i++)
            [
              '${i + 1}',
              items[i].name,
              formatPdfInr(items[i].orderedValue),
            ],
        ],
        numericFrom: 2,
      ),
    ],
  );
}

pw.Widget _materialLine(
  int rank,
  PurchasedMaterial item,
  double maxValue,
  PdfColor accent,
) {
  final pct = maxValue <= 0 ? 0.0 : (item.orderedValue / maxValue).clamp(0.0, 1.0);
  final filled = math.max(1, (pct * 100).round());
  final rest = math.max(1, 100 - filled);
  final name = item.name.length > 40 ? '${item.name.substring(0, 37)}...' : item.name;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.SizedBox(
              width: 16,
              child: pw.Text('$rank.', style: const pw.TextStyle(fontSize: 8)),
            ),
            pw.Expanded(
              child: pw.Text(sanitizePdfText(name), style: const pw.TextStyle(fontSize: 8)),
            ),
            pw.Text(
              formatPdfCompactInr(item.orderedValue),
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Row(
          children: [
            pw.Expanded(
              flex: filled,
              child: pw.Container(height: 4, color: accent),
            ),
            pw.Expanded(
              flex: rest,
              child: pw.Container(height: 4, color: PdfColors.grey300),
            ),
          ],
        ),
      ],
    ),
  );
}
