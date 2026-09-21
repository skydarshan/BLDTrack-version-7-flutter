import '../../core/network/api_client.dart';
import '../dmr/services/dmr_api.dart';
import '../inventory/services/inventory_ops_api.dart';
import '../platform/services/platform_apis.dart';
import '../pms/services/pms_services.dart';
import '../procurement/services/procurement_apis.dart';
import '../settings/services/settings_apis.dart';

/// Single facade for all product APIs after login.
class AppServices {
  AppServices(ApiClient client)
      : pms = PmsServices(client),
        settings = SettingsApis(client),
        rr = RequisitionRequestsApi(client),
        rc = RateComparativesApi(client),
        po = RequisitionOrdersApi(client),
        dmr = DmrApi(client),
        inventory = InventoryOpsApi(client),
        notifications = NotificationsApi(client),
        billing = BillingApi(client);

  final PmsServices pms;
  final SettingsApis settings;
  final RequisitionRequestsApi rr;
  final RateComparativesApi rc;
  final RequisitionOrdersApi po;
  final DmrApi dmr;
  final InventoryOpsApi inventory;
  final NotificationsApi notifications;
  final BillingApi billing;
}
