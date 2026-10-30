import 'package:avidus_product/features/pms/utils/structure_access.dart';
import 'package:avidus_product/features/pms/utils/structure_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty tree is an empty list', () {
    expect(structureTreeRoots({'total': 0, 'tree': []}), isEmpty);
    expect(structureTreeRoots({'total': 0, 'nodes': []}), isEmpty);
    expect(readStructureNodeList({'nodes': []}), isEmpty);
  });

  test('tree keeps children and task counts', () {
    final roots = structureTreeRoots({
      'tree': [
        {
          '_id': 'b',
          'type': 'building',
          'name': 'Tower A',
          'task_count': 0,
          'children': [
            {
              '_id': 'f',
              'type': 'floor',
              'name': 'Basement 1',
              'parent': 'b',
              'level_number': -1,
              'task_count': 2,
              'children': [],
            },
          ],
        },
      ],
    });

    expect(roots, hasLength(1));
    expect(structureChildNodes(roots.first).single['name'], 'Basement 1');
    expect(structureTaskCount(structureChildNodes(roots.first).single), 2);
    expect(
      structureDeleteMessage(structureChildNodes(roots.first).single),
      contains('2 tasks are linked directly'),
    );
  });

  test('flat nodes keep display order when labels are present', () {
    final options = structureNodeOptions([
      {'_id': 'b', 'name': 'Tower A', 'label': 'Tower A', 'type': 'building'},
      {
        '_id': 'f',
        'name': 'Basement 1',
        'label': 'Tower A › Basement 1',
        'type': 'floor',
        'parent': 'b',
      },
    ]);
    expect(options.map((option) => option.label).toList(), [
      'Tower A',
      'Tower A › Basement 1',
    ]);
  });

  test('resolve nodes group by parent', () {
    final groups = groupStructureNodesByParent([
      {'_id': 'u1', 'parent': 'f2', 'name': '201A'},
      {'_id': 'u2', 'parent': 'f2', 'name': '202A'},
      {'_id': 'u3', 'parent': 'f5', 'name': '501A'},
    ]);
    expect(groups['f2']!.map((node) => node['name']), ['201A', '202A']);
    expect(groups['f5']!.single['name'], '501A');
  });

  test('create body follows placement rules and omits site', () {
    final building = structureCreateBody(
      type: 'building',
      parentId: 'should-drop',
      parentType: null,
      name: 'Tower A',
      code: '',
      category: '',
      levelText: '',
      fromLevelText: '',
      toLevelText: '',
    );
    expect(building.payload!.containsKey('site'), isFalse);
    expect(building.payload!.containsKey('parent'), isFalse);
    expect(building.payload!['name'], 'Tower A');

    final floor = structureCreateBody(
      type: 'floor',
      parentId: 'b',
      parentType: 'building',
      name: '',
      code: '',
      category: '',
      levelText: '-1',
      fromLevelText: '',
      toLevelText: '',
    );
    expect(floor.payload!.containsKey('name'), isFalse);
    expect(floor.payload!['level_number'], -1);
    expect(floor.payload!['parent'], 'b');

    final unit = structureCreateBody(
      type: 'unit',
      parentId: 'b',
      parentType: 'building',
      name: '201A',
      code: '201A',
      category: '2BHK',
      levelText: '',
      fromLevelText: '',
      toLevelText: '',
    );
    expect(unit.isValid, isFalse);
    expect(unit.errors['parent'], 'A unit must be placed under a floor');

    final core = structureCreateBody(
      type: 'core',
      parentId: 'b',
      parentType: 'building',
      name: 'Lift',
      code: '',
      category: '',
      levelText: '',
      fromLevelText: '7',
      toLevelText: '3',
    );
    expect(core.errors['from_level'], 'From level cannot be above to level');
  });

  test('patch sends only changed fields and cannot move under a child', () {
    final existing = {
      '_id': 'f',
      'type': 'floor',
      'name': 'Floor 2',
      'code': 'F2',
      'parent': 'b',
      'level_number': 2,
      'category': '',
    };
    final same = structurePatchBody(
      existing: existing,
      parentId: 'b',
      parentType: 'building',
      name: 'Floor 2',
      code: 'F2',
      category: '',
      levelText: '2',
      fromLevelText: '',
      toLevelText: '',
      blockedParentIds: {'f', 'u'},
    );
    expect(same.payload, isEmpty);

    final renamed = structurePatchBody(
      existing: existing,
      parentId: 'b',
      parentType: 'building',
      name: 'Level 2',
      code: '',
      category: 'Residential',
      levelText: '5',
      fromLevelText: '',
      toLevelText: '',
      blockedParentIds: {'f'},
    );
    expect(renamed.payload, {
      'name': 'Level 2',
      'code': '',
      'category': 'Residential',
      'level_number': 5,
    });
    expect(renamed.payload!.containsKey('type'), isFalse);

    final moved = structurePatchBody(
      existing: existing,
      parentId: 'u',
      parentType: 'unit',
      name: 'Floor 2',
      code: 'F2',
      category: '',
      levelText: '2',
      fromLevelText: '',
      toLevelText: '',
      blockedParentIds: {'f', 'u'},
    );
    expect(moved.isValid, isFalse);
    expect(
      moved.errors['parent'],
      'A node cannot be moved under itself or one of its children',
    );
  });

  test('reorder keeps unlisted siblings after the listed ids', () {
    final roots = [
      {
        '_id': 'b',
        'children': [
          {'_id': 'f1', 'parent': 'b', 'children': <Map<String, dynamic>>[]},
          {'_id': 'f2', 'parent': 'b', 'children': <Map<String, dynamic>>[]},
          {'_id': 'f3', 'parent': 'b', 'children': <Map<String, dynamic>>[]},
        ],
      },
    ];
    final next = reorderStructureSiblings(roots, 'b', ['f3', 'f1']);
    expect(
      structureChildNodes(next.single).map((node) => node['_id']),
      ['f3', 'f1', 'f2'],
    );
  });

  test('geometry outside the allowed range is rejected and a change is sent alone', () {
    final invalid = structureCreateBody(
      type: 'external_area',
      parentId: null,
      parentType: null,
      name: 'Deck',
      code: '',
      category: '',
      levelText: '',
      fromLevelText: '',
      toLevelText: '',
      geometryText: {'height': '80'},
    );
    expect(invalid.isValid, isFalse);
    expect(invalid.errors['geometry.height'], contains('0.5'));

    final patched = structurePatchBody(
      existing: {
        '_id': 'b',
        'type': 'building',
        'name': 'Tower A',
        'parent': null,
        'geometry': {'height': 10, 'width': 20},
      },
      parentId: null,
      parentType: null,
      name: 'Tower A',
      code: '',
      category: '',
      levelText: '',
      fromLevelText: '',
      toLevelText: '',
      blockedParentIds: {'b'},
      geometryText: {'height': '4.2', 'width': '20'},
    );
    expect(patched.payload, {
      'geometry': {'height': 4.2},
    });
  });
}
