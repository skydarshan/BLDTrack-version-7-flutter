import 'package:avidus_product/core/network/api_exception.dart';
import 'package:avidus_product/core/utils/form_validation_helpers.dart';
import 'package:avidus_product/features/pms/utils/structure_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('400 keeps the message and highlights the field', () {
    final error = readStructureError(
      ApiException(
        statusCode: 400,
        message: 'A unit must be placed under a floor',
        errors: [
          {'field': 'parent', 'message': 'A unit must be placed under a floor'},
        ],
      ),
    );

    expect(error.highlightFields, isTrue);
    expect(error.message, 'A unit must be placed under a floor');
    expect(error.fieldMessages['parent'], 'A unit must be placed under a floor');
    expect(error.isNoAccess, isFalse);
    expect(error.isNotFound, isFalse);
  });

  test('400 highlights level and core range fields', () {
    final missingLevel = readStructureError(
      ApiException(
        statusCode: 400,
        message: 'A floor needs a level',
        errors: [
          {'field': 'level_number', 'message': 'Level is required'},
        ],
      ),
    );
    expect(missingLevel.fieldMessages['level_number'], 'Level is required');

    final range = readStructureError(
      ApiException(
        statusCode: 400,
        message: 'From level cannot be above to level',
        errors: [
          {'field': 'from_level', 'message': 'From level cannot be above to level'},
          {'field': 'to_level', 'message': 'From level cannot be above to level'},
        ],
      ),
    );
    expect(range.fieldMessages.keys, containsAll(['from_level', 'to_level']));
  });

  test('403 is no access for submodule, permission, and site', () {
    for (final message in [
      'Project Structure is turned off',
      'No update permission',
      "You are not assigned to this project's site",
    ]) {
      final error = readStructureError(ApiException(statusCode: 403, message: message));
      expect(error.isNoAccess, isTrue, reason: message);
      expect(error.highlightFields, isFalse);
    }
  });

  test('404 is not found', () {
    final error = readStructureError(
      ApiException(statusCode: 404, message: 'Node not found'),
    );
    expect(error.isNotFound, isTrue);
    expect(error.notFoundMessage, 'Node not found');

    final empty = readStructureError(ApiException(statusCode: 404, message: ''));
    expect(empty.notFoundMessage, 'Not found');
  });

  test('409 delete conflict reads cascade and unlink_tasks', () {
    final error = readStructureError(
      ApiException(
        statusCode: 409,
        message: 'Delete needs confirmation',
        errors: [
          {'field': 'cascade', 'message': 'Floor 2 has 5 child node(s)'},
          {
            'field': 'unlink_tasks',
            'message': '4 task(s) are linked to Floor 2 or its children',
          },
        ],
      ),
    );

    expect(error.isDeleteConflict, isTrue);
    expect(error.highlightFields, isFalse);
    expect(error.needsCascade, isTrue);
    expect(error.needsUnlinkTasks, isTrue);
    expect(error.messageFor('cascade'), 'Floor 2 has 5 child node(s)');
    expect(
      error.messageFor('unlink_tasks'),
      '4 task(s) are linked to Floor 2 or its children',
    );
    expect(error.fieldMessages.containsKey('cascade'), isFalse);
  });

  test('409 duplicate level can be fixed by changing the field', () {
    final error = readStructureError(
      ApiException(
        statusCode: 409,
        message: 'A floor already uses this level',
        errors: [
          {'field': 'level_number', 'message': 'Level 5 is already used'},
        ],
      ),
    );

    expect(error.isDeleteConflict, isFalse);
    expect(error.highlightFields, isTrue);
    expect(error.fieldMessages['level_number'], 'Level 5 is already used');
  });

  test('409 tower clash highlights the building name or code', () {
    final name = readStructureError(
      ApiException(
        statusCode: 409,
        message: 'This tower clashes with the existing structure',
        errors: [
          {'field': 'building.name', 'message': 'Tower A already exists'},
        ],
      ),
    );
    expect(name.highlightFields, isTrue);
    expect(name.fieldMessages['name'], 'Tower A already exists');

    final code = readStructureError(
      ApiException(
        statusCode: 409,
        message: 'This tower clashes with the existing structure',
        errors: [
          {'field': 'code', 'message': 'Code A is already used'},
        ],
      ),
    );
    expect(code.fieldMessages['code'], 'Code A is already used');

    final buildingCode = readStructureError(
      ApiException(
        statusCode: 409,
        message: 'This tower clashes with the existing structure',
        errors: [
          {'field': 'building.code', 'message': 'Code A is already used'},
        ],
      ),
    );
    expect(buildingCode.fieldMessages['code'], 'Code A is already used');
  });

  test('task link fields highlight Structure', () {
    final otherProject = readStructureError(
      ApiException(
        statusCode: 400,
        message: 'That node belongs to another project',
        errors: [
          {'field': 'structure_nodes', 'message': 'That node belongs to another project'},
        ],
      ),
    );
    expect(otherProject.fieldMessages['structure'], 'That node belongs to another project');

    final outside = readStructureError(
      ApiException(
        statusCode: 400,
        message: 'Floor level is outside the core range',
        errors: [
          {
            'field': 'structure_nodes[0].floor_level',
            'message': 'Floor level is outside the core range',
          },
        ],
      ),
    );
    expect(outside.fieldMessages['structure'], 'Floor level is outside the core range');
    expect(
      apiFieldErrors(
        ApiException(
          statusCode: 400,
          message: 'Floor level is outside the core range',
          errors: [
            {
              'field': 'structure_nodes[0].floor_level',
              'message': 'Floor level is outside the core range',
            },
          ],
        ),
      ),
      {'structure': 'Floor level is outside the core range'},
    );
  });
}
