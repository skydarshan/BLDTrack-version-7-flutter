import 'package:avidus_product/features/settings/utils/module_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads permissions from the grouped catalog response', () {
    final defs = permissionDefsFromResponse({
      'data': {
        'permissions': [
          {'module': 'site', 'description': 'read access for Sites'},
        ],
        'grouped': {
          'user': [
            {'module': 'user', 'description': 'read access for Users'},
          ],
        },
      },
    });
    expect(modulesFromPermissionDefs(defs).map((row) => row['name']), ['site', 'user']);
  });

  test('permission defs become one row per module', () {
    final rows = modulesFromPermissionDefs([
      {
        'module': 'user',
        'action': 'read',
        'description': 'read access for Users',
      },
      {
        'module': 'user',
        'action': 'create',
        'description': 'create access for Users',
      },
      {
        'module': 'projectstructure',
        'action': 'read',
        'description': 'read access for Project Structure',
      },
      {
        'module': 'material-issue',
        'action': 'view',
        'description': 'view access for Material Issue',
      },
    ]);

    expect(rows.map((row) => row['name']).toList(), [
      'material-issue',
      'projectstructure',
      'user',
    ]);
    expect(rows[0]['displayName'], 'Material Issue');
    expect(rows[1]['displayName'], 'Project Structure');
    expect(rows[2]['displayName'], 'Users');
  });
}
