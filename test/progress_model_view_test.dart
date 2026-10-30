import 'package:avidus_product/features/pms/utils/progress_model_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final model = {
    'buildings': [
      {
        'node_id': 'b1',
        'type': 'building',
        'name': 'Tower A',
        'floors': [
          {
            'node_id': 'f0',
            'type': 'floor',
            'name': 'Ground Floor',
            'level_number': 0,
            'units': [],
            'common_areas': [
              {'node_id': 'lobby', 'type': 'common_area', 'name': 'Lobby'},
            ],
          },
          {
            'node_id': 'f5',
            'type': 'floor',
            'name': 'Floor 5',
            'level_number': 5,
            'units': [
              {'node_id': 'u1', 'type': 'unit', 'name': '501A'},
            ],
            'common_areas': [
              {'node_id': 'l5', 'type': 'common_area', 'name': 'Lobby'},
            ],
          },
          {
            'node_id': 'empty',
            'type': 'floor',
            'name': 'Terrace',
            'level_number': 6,
            'units': [],
            'common_areas': [],
          },
        ],
        'cores': [
          {'node_id': 'lift', 'type': 'core', 'name': 'Lift 1'},
        ],
      },
    ],
    'external_areas': [
      {'node_id': 'club', 'type': 'external_area', 'name': 'Clubhouse'},
    ],
  };

  test('floors are listed by level_number from low to high', () {
    final stacked = stackedModelFromGeometry(model);
    expect(stacked.buildings.single.floors.map((f) => f.node.name).toList(), [
      'Ground Floor',
      'Floor 5',
      'Terrace',
    ]);
  });

  test('units and common areas stay under their floor', () {
    final floor = stackedModelFromGeometry(model).buildings.single.floors[1];
    expect(floor.children.map((c) => c.nodeId).toList(), ['u1', 'l5']);
    expect(floor.children.map((c) => c.type).toList(), ['unit', 'common_area']);
  });

  test('a floor with no children is still the floor itself', () {
    final floor = stackedModelFromGeometry(model)
        .buildings
        .single
        .floors
        .firstWhere((f) => f.node.name == 'Terrace');
    expect(floor.children, isEmpty);
    expect(floor.node.type, 'floor');
  });

  test('cores and external areas are included', () {
    final stacked = stackedModelFromGeometry(model);
    expect(stacked.buildings.single.cores.single.nodeId, 'lift');
    expect(stacked.externalAreas.single.name, 'Clubhouse');
    expect(stacked.externalAreas.single.type, 'external_area');
  });

  test('node detail follows the structure mental model', () {
    const unit = StackedCell(
      nodeId: 'u',
      name: '501A',
      type: 'unit',
      code: '501A',
      category: '2BHK',
    );
    const core = StackedCell(
      nodeId: 'c',
      name: 'Lift 1',
      type: 'core',
      fromLevel: -1,
      toLevel: 6,
    );
    const floor = StackedCell(
      nodeId: 'f',
      name: 'Basement 1',
      type: 'floor',
      levelNumber: -1,
    );
    expect(structureNodeDetail(unit), 'Unit · code 501A · 2BHK');
    expect(structureNodeDetail(core), 'Core · levels -1 → 6');
    expect(structureNodeDetail(floor), 'Floor · level -1');
    expect(
      coreFloorLevelNotes({
        'structure_nodes': [
          {'node': 'lift', 'floor_level': 3},
        ],
      }),
      ['at level 3'],
    );
  });

  test('cached model must contain every progress node', () {
    final nodes = indexProgressNodes([
      {'node_id': 'b1'},
      {'node_id': 'missing'},
    ]);
    expect(modelCoversProgressNodes(model, nodes.keys), isFalse);
    expect(
      modelCoversProgressNodes(model, ['b1', 'f5', 'u1', 'lift', 'club']),
      isTrue,
    );
  });

  test('colours and legend labels come from the API values', () {
    expect(colorValueFromHex('#EF4444'), 0xFFEF4444);
    expect(colorValueFromHex('nope'), isNull);
    const legend = [
      {'key': 'in_progress', 'label': 'In progress', 'color': '#FACC15'},
    ];
    expect(legendLabel(legend, 'in_progress'), 'In progress');
    expect(legendColor(legend, 'in_progress'), '#FACC15');
    expect(formatProgressPercent(33.4), '33.4%');
    expect(formatProgressPercent(100), '100%');
  });

  test('empty structure_nodes means the task inherits its link', () {
    expect(taskInheritsStructureLink({'structure_nodes': []}), isTrue);
    expect(
      taskInheritsStructureLink({
        'structure_nodes': [
          {'node': 'x'},
        ],
      }),
      isFalse,
    );
    expect(taskPathLabel(['Floor 2 finishing']), 'Floor 2 finishing');
    expect(
      assignedMembersOf({
        'assignedMembers': [
          {'name': 'Ravi', 'email': 'ravi@example.com'},
        ],
      }).single['name'],
      'Ravi',
    );
  });
}
