import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/org/org_modules.dart';
import '../features/app/app_shell.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/dmr/screens/dmr_screens.dart';
import '../features/inventory/screens/inventory_screens.dart';
import '../features/org/org_session.dart';
import '../features/platform/screens/platform_screens.dart';
import '../features/pms/screens/pms_home_screen.dart';
import '../features/pms/screens/project_detail_screen.dart';
import '../features/pms/screens/project_form_screen.dart';
import '../features/pms/screens/projects_list_screen.dart';
import '../features/pms/screens/task_approvals_screen.dart';
import '../features/pms/screens/task_detail_screen.dart';
import '../features/pms/screens/task_form_screen.dart';
import '../features/pms/screens/tasks_list_screen.dart';
import '../features/pms/screens/template_form_screen.dart';
import '../features/pms/screens/templates_list_screen.dart';
import '../features/procurement/screens/procurement_screens.dart';
import '../features/procurement/screens/rc_po_screens.dart';
import '../features/settings/screens/app_settings_screen.dart';
import '../features/settings/screens/audit_logs_screen.dart';
import '../features/settings/screens/companies_screen.dart';
import '../features/settings/screens/contractors_screen.dart';
import '../features/settings/screens/items_screen.dart';
import '../features/settings/screens/organization_screen.dart';
import '../features/settings/screens/roles_screen.dart';
import '../features/settings/screens/settings_hub_screen.dart';
import '../features/settings/screens/simple_masters_screens.dart';
import '../features/settings/screens/site_staff_screen.dart';
import '../features/settings/screens/sites_screen.dart';
import '../features/settings/screens/sub_categories_screen.dart';
import '../features/settings/screens/users_screen.dart';
import '../features/settings/screens/vendors_screen.dart';

import '../router/app_router_refresh.dart';

GoRouter createAppRouter(
  AuthProvider auth,
  OrgSession orgSession,
  AppRouterRefresh refresh,
) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = auth.status;
      final loggingIn = state.matchedLocation == '/login';
      final registering = state.matchedLocation == '/register';
      final onAuthPage = loggingIn || registering;

      if (status == AuthStatus.unknown) return null;

      if (status == AuthStatus.unauthenticated && !onAuthPage) {
        return '/login';
      }

      if (status == AuthStatus.authenticated && onAuthPage) {
        return workspaceHomePath(orgSession.workspace);
      }

      if (status == AuthStatus.authenticated) {
        final path = state.uri.path;
        final required = workspaceForPath(path);
        if (required != null && !orgSession.canAccessWorkspace(required)) {
          return workspaceHomePath(orgSession.workspace);
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/dashboard',
        redirect: (_, _) => workspaceHomePath(orgSession.workspace),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const ProcurementHomeScreen()),
          GoRoute(path: '/more', builder: (_, _) => const MoreHubScreen()),
          GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
          GoRoute(path: '/billing', builder: (_, _) => const BillingScreen()),

          GoRoute(path: '/procurement/rr', builder: (_, _) => const RrListScreen()),
          GoRoute(path: '/procurement/rr/new', builder: (_, _) => const RrCreateScreen()),
          GoRoute(
            path: '/procurement/rr/:id',
            builder: (_, state) => RrDetailScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(path: '/procurement/approvals', builder: (_, _) => const RrApprovalsScreen()),
          GoRoute(path: '/procurement/rc', builder: (_, _) => const RcListScreen()),
          GoRoute(
            path: '/procurement/rc/:id',
            builder: (_, state) => RcDetailScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(path: '/procurement/rate-approvals', builder: (_, _) => const RateApprovalsScreen()),
          GoRoute(path: '/procurement/po', builder: (_, _) => const PoListScreen()),
          GoRoute(
            path: '/procurement/po/:id',
            builder: (_, state) => PoDetailScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(path: '/procurement/rr-status', builder: (_, _) => const RrStatusScreen()),

          GoRoute(path: '/dmr/create', builder: (_, _) => const DmrCreateScreen()),
          GoRoute(path: '/dmr/status', builder: (_, _) => const DmrStatusScreen()),
          GoRoute(
            path: '/dmr/status/:id',
            builder: (_, state) => DmrOrderDetailScreen(id: state.pathParameters['id']!),
          ),

          GoRoute(path: '/inventory', builder: (_, _) => const InventoryHomeScreen()),
          GoRoute(path: '/inventory/imr', builder: (_, _) => const ImrListScreen()),
          GoRoute(path: '/inventory/imr/new', builder: (_, _) => const ImrCreateScreen()),
          GoRoute(path: '/inventory/transfers', builder: (_, _) => const TransferListScreen()),
          GoRoute(path: '/inventory/transfers/new', builder: (_, _) => const TransferCreateScreen()),
          GoRoute(
            path: '/inventory/transfers/:id',
            builder: (_, state) => TransferDetailScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(path: '/inventory/scrap', builder: (_, _) => const ScrapListScreen()),
          GoRoute(path: '/inventory/scrap/new', builder: (_, _) => const ScrapCreateScreen()),
          GoRoute(
            path: '/inventory/scrap/:id',
            builder: (_, state) => ScrapDetailScreen(id: state.pathParameters['id']!),
          ),

          GoRoute(path: '/pms', builder: (_, _) => const PmsHomeScreen()),
          GoRoute(path: '/pms/projects', builder: (_, _) => const ProjectsListScreen()),
          GoRoute(path: '/pms/projects/new', builder: (_, _) => const ProjectFormScreen()),
          GoRoute(
            path: '/pms/projects/:id',
            builder: (_, state) => ProjectDetailScreen(projectId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/pms/projects/:id/edit',
            builder: (_, state) => ProjectFormScreen(projectId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/pms/tasks',
            builder: (_, state) => TasksListScreen(
              initialMine: state.uri.queryParameters['mine'] == '1',
            ),
          ),
          GoRoute(
            path: '/pms/tasks/new',
            builder: (_, state) => TaskFormScreen(
              initialProjectId: state.uri.queryParameters['project'],
            ),
          ),
          GoRoute(
            path: '/pms/tasks/:id',
            builder: (_, state) => TaskDetailScreen(taskId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/pms/tasks/:id/edit',
            builder: (_, state) => TaskFormScreen(taskId: state.pathParameters['id']),
          ),
          GoRoute(path: '/pms/approvals', builder: (_, _) => const TaskApprovalsScreen()),
          GoRoute(path: '/pms/templates', builder: (_, _) => const TemplatesListScreen()),
          GoRoute(path: '/pms/templates/new', builder: (_, _) => const TemplateFormScreen()),
          GoRoute(
            path: '/pms/templates/:id/edit',
            builder: (_, state) => TemplateFormScreen(templateId: state.pathParameters['id']),
          ),
          GoRoute(path: '/pms/settings', builder: (_, _) => const SettingsHubScreen()),
          GoRoute(path: '/pms/settings/app', builder: (_, _) => const AppSettingsScreen()),
          GoRoute(path: '/pms/settings/users', builder: (_, _) => const UsersScreen()),
          GoRoute(path: '/pms/settings/roles', builder: (_, _) => const RolesScreen()),
          GoRoute(path: '/pms/settings/organization', builder: (_, _) => const OrganizationScreen()),
          GoRoute(path: '/pms/settings/locations', builder: (_, _) => const LocationsScreen()),
          GoRoute(path: '/pms/settings/companies', builder: (_, _) => const CompaniesScreen()),
          GoRoute(path: '/pms/settings/sites', builder: (_, _) => const SitesScreen()),
          GoRoute(path: '/pms/settings/site-staff', builder: (_, _) => const SiteStaffScreen()),
          GoRoute(path: '/pms/settings/contractors', builder: (_, _) => const ContractorsScreen()),
          GoRoute(path: '/pms/settings/activities', builder: (_, _) => const ActivitiesScreen()),
          GoRoute(path: '/pms/settings/sub-activities', builder: (_, _) => const SubActivitiesScreen()),
          GoRoute(path: '/pms/settings/uoms', builder: (_, _) => const UomsScreen()),
          GoRoute(path: '/pms/settings/gsts', builder: (_, _) => const GstsScreen()),
          GoRoute(path: '/pms/settings/brands', builder: (_, _) => const BrandsScreen()),
          GoRoute(path: '/pms/settings/categories', builder: (_, _) => const CategoriesScreen()),
          GoRoute(path: '/pms/settings/sub-categories', builder: (_, _) => const SubCategoriesScreen()),
          GoRoute(path: '/pms/settings/vendors', builder: (_, _) => const VendorsScreen()),
          GoRoute(path: '/pms/settings/items', builder: (_, _) => const ItemsScreen()),
          GoRoute(path: '/pms/settings/misc-configs', builder: (_, _) => const MiscConfigsScreen()),
          GoRoute(path: '/pms/settings/audit-logs', builder: (_, _) => const AuditLogsScreen()),
        ],
      ),
    ],
  );
}
