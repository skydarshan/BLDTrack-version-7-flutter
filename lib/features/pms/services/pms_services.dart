import '../../../core/network/api_client.dart';
import 'dashboard_api.dart';
import 'masters_api.dart';
import 'project_templates_api.dart';
import 'projects_api.dart';
import 'tasks_api.dart';

/// Shared PMS API facade injected via Provider.
class PmsServices {
  PmsServices(ApiClient client)
      : dashboard = DashboardApi(client),
        projects = ProjectsApi(client),
        tasks = TasksApi(client),
        templates = ProjectTemplatesApi(client),
        masters = MastersApi(client);

  final DashboardApi dashboard;
  final ProjectsApi projects;
  final TasksApi tasks;
  final ProjectTemplatesApi templates;
  final MastersApi masters;
}
