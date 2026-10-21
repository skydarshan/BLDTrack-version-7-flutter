import 'package:avidus_product/features/dashboard/pdf/dashboard_pdf.dart';
import 'package:avidus_product/features/dashboard/utils/dashboard_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default range starts on the first of the month', () {
    final range = defaultDashboardDateRange(DateTime(2026, 10, 16));
    expect(range.dateFrom, '2026-10-01');
    expect(range.dateTo, '2026-10-16');
  });

  test('indian grouping and compact rupee text match the website PDF', () {
    expect(formatIndianDigits(1234567, 0), '12,34,567');
    expect(formatPdfInr(1234.5), 'Rs. 1,234.50');
    expect(formatPdfCompactInr(15000000), 'Rs. 1.50 Cr');
    expect(formatPdfCompactInr(250000), 'Rs. 2.50 L');
  });

  test('chart scale uses the website step sizes', () {
    final small = buildChartYScale(10);
    expect(small.max, 10);
    expect(small.ticks, [0, 5, 10]);

    final empty = buildChartYScale(0);
    expect(empty.max, 5);
    expect(empty.ticks, [0, 5]);
  });

  test('overview and procurement payloads keep chart buckets and sites', () {
    final overview = normalizeDashboardOverview({
      'remaining_inventory': {'value': 1000, 'value_formatted': '₹1,000'},
      'active_sites': {'count': 2, 'status_label': 'All Operational'},
      'items_yet_to_be_received': {'value': 50, 'pending_line_items': 3},
      'total_purchase_requests': {'count': 8, 'pending_count': 1},
      'site_wise_purchase_requests': [
        {'site_id': 's1', 'site_name': 'North yard', 'site_code': 'NY', 'prs_raised': 4},
      ],
    });
    expect(overview.prCount, 8);
    expect(overview.sites.single.displayName, 'NY');
    expect(overview.sites.single.prsRaised, 4);

    final procurement = normalizeProcurementOverview({
      'procurement_value': {
        'granularity': 'day',
        'buckets': [
          {'label': '01', 'ordered': 200000, 'received': 100000},
        ],
      },
      'top_purchased_materials': [
        {'item_name': 'Cement', 'ordered_value': 90000, 'received_value': 40000},
      ],
      'least_purchased_materials': [],
    });
    expect(procurement.granularity, 'day');
    expect(procurement.buckets.single.ordered, 200000);
    expect(procurement.top.single.displayValue, 40000);
  });

  test('assigned users see their sites even when the API omits a zero row', () {
    final rows = visibleSiteRows(
      apiRows: const [
        SitePrRow(
          siteId: 's1',
          siteName: 'North',
          siteCode: 'NY',
          displayName: 'NY',
          prsRaised: 3,
        ),
      ],
      unrestricted: false,
      assignedSites: const [
        {'_id': 's1', 'site_name': 'North', 'site_code': 'NY'},
        {'_id': 's2', 'site_name': 'South', 'site_code': 'SY'},
      ],
    );
    expect(rows.map((row) => row.prsRaised), [3, 0]);
    expect(rows.last.displayName, 'SY');
  });

  test('pdf export includes the overview header', () async {
    final bytes = await buildDashboardPdfBytes(
      overview: DashboardOverview.empty,
      procurement: const ProcurementOverview(
        granularity: 'week',
        buckets: [
          ProcurementBucket(label: 'W1', key: 'w1', ordered: 100000, received: 40000),
        ],
        top: [
          PurchasedMaterial(name: 'Cement', orderedValue: 80000, receivedValue: 10000),
        ],
        least: [],
      ),
      chartGranularity: 'week',
      siteLabel: 'All sites',
      dateFrom: '2026-10-01',
      dateTo: '2026-10-16',
      generatedAt: DateTime(2026, 10, 16, 9, 30),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(800));
  });
}
