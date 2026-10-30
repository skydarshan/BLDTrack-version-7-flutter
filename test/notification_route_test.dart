import 'package:avidus_product/core/network/api_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification routes follow the web link when it maps', () {
    expect(
      notificationRouteFor({
        'link': '/tasks/507f1f77bcf86cd799439011',
        'entityType': 'project',
      }),
      '/pms/tasks/507f1f77bcf86cd799439011',
    );
  });

  test('notification routes fall back to entity type', () {
    expect(
      notificationRouteFor({
        'entityType': 'requisition_request',
        'entityId': '507f1f77bcf86cd799439012',
      }),
      '/procurement/rr/507f1f77bcf86cd799439012',
    );
    expect(
      notificationRouteFor({'type': 'dpr_missing'}),
      '/pms/dpr?tab=missing',
    );
    expect(notificationRouteFor({'title': 'Hello'}), '/notifications');
  });

  test('notification routes cover live alert types', () {
    expect(
      notificationRouteFor({
        'type': 'task_assigned',
        'entityId': '507f1f77bcf86cd799439011',
      }),
      '/pms/tasks/507f1f77bcf86cd799439011',
    );
    expect(
      notificationRouteFor({'type': 'rr_approval_pending'}),
      '/procurement/approvals',
    );
    expect(
      notificationRouteFor({'type': 'inventory_material_issued'}),
      '/inventory/imr',
    );
    expect(
      notificationRouteFor({
        'link': '/dashboard/projects/507f1f77bcf86cd799439011/tasks/507f1f77bcf86cd799439012',
      }),
      '/pms/tasks/507f1f77bcf86cd799439012',
    );
  });
}
