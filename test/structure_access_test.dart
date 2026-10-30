import 'package:avidus_product/core/network/api_exception.dart';
import 'package:avidus_product/core/org/org_modules.dart';
import 'package:avidus_product/features/pms/utils/site_access.dart';
import 'package:avidus_product/features/pms/utils/structure_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('structure can be read when tasks or progress model is on', () {
    final tasksOnly = normalizeOrgModules({
      'project_management': {
        'enabled': true,
        'submodules': {'tasks': true, 'structure': false, 'progress_model': false},
      },
    });
    expect(orgCanReadStructure({'modules': tasksOnly}), isTrue);

    final modelOnly = normalizeOrgModules({
      'project_management': {
        'enabled': true,
        'submodules': {'progress_model': true},
      },
    });
    expect(orgCanReadStructure({'modules': modelOnly}), isTrue);

    final none = normalizeOrgModules({
      'project_management': {
        'enabled': true,
        'submodules': {'projects': true},
      },
    });
    expect(orgCanReadStructure({'modules': none}), isFalse);
  });

  test('missing structure stays off for an existing organisation', () {
    final normalized = normalizeOrgModules({
      'project_management': {
        'enabled': true,
        'submodules': {'projects': true, 'tasks': true},
      },
    });
    final subs = (normalized['project_management'] as Map)['submodules'] as Map;
    expect(subs['structure'], isFalse);
    expect(subs['progress_model'], isFalse);
  });

  test('role rows show with Project Management', () {
    final org = {
      'modules': normalizeOrgModules({
        'project_management': {
          'enabled': true,
          'submodules': {'projects': true, 'structure': false, 'progress_model': false},
        },
      }),
    };
    expect(offerRolePermissionModule('projectstructure', org, alreadyOnRole: false), isTrue);
    expect(offerRolePermissionModule('projectmodel', org, alreadyOnRole: false), isTrue);
    expect(offerRolePermissionModule('activity', org, alreadyOnRole: false), isTrue);
    expect(offerRolePermissionModule('task', org, alreadyOnRole: false), isTrue);

    final off = {
      'modules': normalizeOrgModules({
        'procurement': {'enabled': true, 'submodules': {'requisition': true}},
      }),
    };
    expect(offerRolePermissionModule('projectstructure', off, alreadyOnRole: false), isFalse);
    expect(offerRolePermissionModule('projectmodel', off, alreadyOnRole: true), isTrue);
  });

  test('structure picker labels keep the parent path', () {
    final options = structureNodeOptions([
      {'_id': 'b', 'name': 'Tower A', 'type': 'building'},
      {'_id': 'f', 'name': 'Level 3', 'type': 'floor', 'parent': 'b'},
      {'_id': 'u', 'name': '301', 'type': 'unit', 'parent': 'f'},
    ]);
    expect(options.map((o) => o.label).toList(), [
      'Tower A / Level 3 / 301 · Unit',
      'Tower A / Level 3 · Floor',
      'Tower A · Building',
    ]);
  });

  test('save payload sends structure modules the organisation document omitted', () {
    final raw = {
      'project_management': {
        'enabled': true,
        'submodules': {
          'projects': true,
          'templates': true,
          'tasks': true,
          'task_progress': true,
          'dpr': true,
        },
      },
    };
    expect(unsupportedSubmoduleKeys(raw), isNot(contains('structure')));
    expect(unsupportedSubmoduleKeys(raw), isNot(contains('progress_model')));
    final edited = normalizeOrgModules(raw);
    final pm = Map<String, dynamic>.from(edited['project_management'] as Map);
    final subs = Map<String, dynamic>.from(pm['submodules'] as Map);
    subs['structure'] = true;
    subs['progress_model'] = true;
    pm['submodules'] = subs;
    edited['project_management'] = pm;

    final payload = modulesPayloadForServer(edited: edited, rawStored: raw);
    final sent = (payload['project_management'] as Map)['submodules'] as Map;
    expect(sent['structure'], isTrue);
    expect(sent['progress_model'], isTrue);
    expect(sent['tasks'], isTrue);
  });

  test('save payload keeps submodule keys the API returned', () {
    final raw = {
      'project_management': {
        'enabled': true,
        'submodules': {
          'tasks': true,
          'structure': false,
          'progress_model': false,
        },
      },
    };
    final edited = normalizeOrgModules(raw);
    final pm = Map<String, dynamic>.from(edited['project_management'] as Map);
    final subs = Map<String, dynamic>.from(pm['submodules'] as Map);
    subs['structure'] = true;
    subs['progress_model'] = true;
    pm['submodules'] = subs;
    edited['project_management'] = pm;

    final payload = modulesPayloadForServer(edited: edited, rawStored: raw);
    final sent = (payload['project_management'] as Map)['submodules'] as Map;
    expect(sent['structure'], isTrue);
    expect(sent['progress_model'], isTrue);
    expect(unsupportedSubmoduleKeys(raw), isNot(contains('structure')));
    expect(unsupportedSubmoduleKeys(raw), isNot(contains('progress_model')));
  });

  test('site 403 is a no-access result, not a list error', () {
    expect(
      isSiteAccessDenied(
        ApiException(statusCode: 403, message: "You are not assigned to this project's site"),
      ),
      isTrue,
    );
    expect(
      isSiteAccessDenied(ApiException(statusCode: 403, message: 'No update permission')),
      isFalse,
    );
    expect(
      isSiteAccessDenied(ApiException(statusCode: 404, message: 'You are not assigned')),
      isFalse,
    );
  });
}
