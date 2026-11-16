import 'package:avidus_product/features/pms/screens/structure_from_tasks_screen.dart';
import 'package:avidus_product/features/pms/utils/structure_errors.dart';
import 'package:avidus_product/features/pms/utils/structure_from_tasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('task titles find towers, floors, and leave linked tasks alone', () {
    expect(parseStructureTaskTitle('Tower A › Level 3 › Slab')!.buildingName, 'Tower A');
    expect(parseStructureTaskTitle('Tower A › Level 3 › Slab')!.level, 3);
    expect(parseStructureTaskTitle('Block 2 / GF')!.floorName, 'Ground Floor');
    expect(parseStructureTaskTitle('Wing B / B1')!.level, -1);
    expect(parseStructureTaskTitle('Villa 4 / Roof')!.terrace, isTrue);
    expect(parseStructureTaskTitle('3rd Floor slab'), isNull);

    final preview = planStructureFromTasks(
      tasks: [
        {
          '_id': 'tower',
          'title': 'Tower A',
          'children': [
            {
              '_id': 'level',
              'title': 'Level 3',
              'children': [
                {'_id': 'slab', 'title': 'Slab', 'children': []},
              ],
            },
          ],
        },
        {
          '_id': 'ground',
          'title': 'Block 2 / Stilt',
          'structure_nodes': [
            {'node': 'already'},
          ],
        },
        {'_id': 'base', 'title': 'Wing B / Basement 1 / Parking'},
      ],
      nodes: [
        {'_id': 'b', 'type': 'building', 'name': 'Tower A'},
        {'_id': 'f3', 'type': 'floor', 'name': 'Level 3', 'parent': 'b', 'level_number': 3},
      ],
    );

    final plan = readFromTasksPlan(preview!)!;
    expect(plan.buildingsNew, 1);
    expect(plan.floorsNew, 1);
    expect(plan.tasksAlreadyLinked, 1);
    final tower = plan.buildings.singleWhere((building) => building.name == 'Tower A');
    expect(tower.exists, isTrue);
    expect(tower.tasksToLink.single.id, 'tower');
    expect(tower.floors.single.exists, isTrue);
    expect(tower.floors.single.tasksToLink.map((task) => task.id), ['level', 'slab']);
    final basement = plan.buildings.singleWhere((building) => building.name == 'Wing B').floors.single;
    expect(basement.name, 'Basement 1');
    expect(basement.levelNumber, -1);
    expect(planStructureFromTasks(tasks: [
      {'_id': 'x', 'title': 'Pour slab'},
    ], nodes: const []), isNull);
  });

  test('preview plan reads buildings, floors, counts, and warnings', () {
    final plan = readFromTasksPlan({
      'preview': true,
      'counts': {
        'buildings_new': 1,
        'floors_new': 1,
        'tasks_to_link': 2,
        'tasks_already_linked': 0,
      },
      'warnings': ['Level text was ambiguous'],
      'buildings': [
        {
          'name': 'Tower B',
          'node_id': null,
          'exists': false,
          'tasks_to_link': [
            {'_id': 'task-building', 'title': 'Tower B'},
          ],
          'floors': [
            {
              'name': 'Floor 2',
              'level_number': 2,
              'node_id': null,
              'exists': false,
              'tasks_to_link': [
                {'_id': 'task-floor', 'title': 'Level 2 slab'},
              ],
            },
          ],
        },
      ],
    });

    expect(plan, isNotNull);
    expect(plan!.canCommit, isTrue);
    expect(plan.buildingsNew, 1);
    expect(plan.floorsNew, 1);
    expect(plan.tasksToLink, 2);
    expect(plan.tasksAlreadyLinked, 0);
    expect(plan.warnings, ['Level text was ambiguous']);
    expect(fromTasksSummary(plan), '1 new building, 1 new floor, 2 tasks to link');

    final building = plan.buildings.single;
    expect(building.name, 'Tower B');
    expect(building.exists, isFalse);
    expect(building.nodeId, isNull);
    expect(building.tasksToLink.single.title, 'Tower B');

    final floor = building.floors.single;
    expect(floor.name, 'Floor 2');
    expect(floor.levelNumber, 2);
    expect(floor.exists, isFalse);
    expect(fromTasksFloorSubtitle(floor), 'Floor · level 2 · New');
    expect(floor.tasksToLink.single.id, 'task-floor');
  });

  test('existing buildings and floors are not counted as new', () {
    final plan = readFromTasksPlan({
      'preview': true,
      'counts': {
        'buildings_new': 0,
        'floors_new': 0,
        'tasks_to_link': 0,
        'tasks_already_linked': 3,
      },
      'warnings': const [],
      'buildings': [
        {
          'name': 'Tower A',
          'node_id': 'building-1',
          'exists': true,
          'tasks_to_link': const [],
          'floors': [
            {
              'name': 'Ground Floor',
              'level_number': 0,
              'node_id': 'floor-1',
              'exists': true,
              'tasks_to_link': const [],
            },
          ],
        },
      ],
    });

    expect(plan!.canCommit, isFalse);
    expect(plan.buildings.single.exists, isTrue);
    expect(plan.buildings.single.floors.single.levelNumber, 0);
    expect(fromTasksSummary(plan), '3 tasks are already linked. Nothing new to add.');
    expect(
      fromTasksResultMessage(createdNodes: 1, linkedTasks: 2),
      'Added 1 node. Linked 2 tasks.',
    );
  });

  test('a commit payload is not treated as a preview', () {
    expect(
      readFromTasksPlan({
        'preview': false,
        'created_nodes': 2,
        'linked_tasks': 2,
        'counts': {'buildings_new': 1, 'floors_new': 1, 'tasks_to_link': 2},
        'buildings': const [],
      }),
      isNull,
    );
  });

  testWidgets('preview lists the tasks to link and build commits', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var previews = 0;
    Map<String, dynamic>? committed;

    await _open(
      tester,
      StructureFromTasksScreen(
        onPreview: () async {
          previews += 1;
          return _samplePreview(alreadyLinked: 1);
        },
        onCommit: () async {
          committed = {'preview': false, 'created_nodes': 2, 'linked_tasks': 2};
          return committed;
        },
      ),
    );

    expect(previews, 1);
    expect(find.textContaining('Ground Floor'), findsOneWidget);
    expect(find.textContaining('Villa 4'), findsOneWidget);
    expect(
      find.text('1 new building, 1 new floor, 2 tasks to link. 1 task is already linked'),
      findsOneWidget,
    );
    expect(find.text('Tower B'), findsWidgets);
    expect(find.text('Level 2 slab'), findsOneWidget);
    expect(find.text('Floor 2'), findsOneWidget);
    expect(find.text('New'), findsNWidgets(2));
    expect(find.text('Level text was ambiguous'), findsOneWidget);

    await tester.tap(find.byKey(const Key('from-tasks-build')));
    await tester.pumpAndSettle();

    expect(committed?['created_nodes'], 2);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('nothing detected keeps build off the screen', (tester) async {
    await _open(
      tester,
      StructureFromTasksScreen(
        onPreview: () async => const StructureApiError(
          statusCode: 400,
          message: 'No buildings or floors were found in task titles.',
        ),
        onCommit: () async => throw StateError('commit should not run'),
      ),
    );

    expect(find.text('No buildings or floors were found in task titles.'), findsOneWidget);
    expect(find.byKey(const Key('from-tasks-build')), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('an already linked plan cannot be built again', (tester) async {
    await _open(
      tester,
      StructureFromTasksScreen(
        onPreview: () async => {
          'preview': true,
          'counts': {
            'buildings_new': 0,
            'floors_new': 0,
            'tasks_to_link': 0,
            'tasks_already_linked': 1,
          },
          'warnings': const <String>[],
          'buildings': [
            {
              'name': 'Block 2',
              'node_id': 'b',
              'exists': true,
              'tasks_to_link': const <Map<String, dynamic>>[],
              'floors': const <Map<String, dynamic>>[],
            },
          ],
        },
        onCommit: () async => throw StateError('commit should not run'),
      ),
    );

    expect(find.text('Existing'), findsOneWidget);
    expect(find.textContaining('Nothing new to add'), findsWidgets);
    final button = tester.widget<FilledButton>(find.byKey(const Key('from-tasks-build')));
    expect(button.onPressed, isNull);
  });

  testWidgets('no access closes the preview', (tester) async {
    await _open(
      tester,
      StructureFromTasksScreen(
        onPreview: () async => const StructureApiError(
          statusCode: 403,
          message: 'You do not have access to this project.',
        ),
        onCommit: () async => const {},
      ),
    );

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Build from tasks'), findsNothing);
  });
}

Map<String, dynamic> _samplePreview({int alreadyLinked = 0}) {
  return {
    'preview': true,
    'counts': {
      'buildings_new': 1,
      'floors_new': 1,
      'tasks_to_link': 2,
      'tasks_already_linked': alreadyLinked,
    },
    'warnings': ['Level text was ambiguous'],
    'buildings': [
      {
        'name': 'Tower B',
        'node_id': null,
        'exists': false,
        'tasks_to_link': [
          {'_id': 'task-building', 'title': 'Tower B'},
        ],
        'floors': [
          {
            'name': 'Floor 2',
            'level_number': 2,
            'node_id': null,
            'exists': false,
            'tasks_to_link': [
              {'_id': 'task-floor', 'title': 'Level 2 slab'},
            ],
          },
        ],
      },
    ],
  };
}

Future<void> _open(WidgetTester tester, StructureFromTasksScreen screen) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => screen),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump();
}
