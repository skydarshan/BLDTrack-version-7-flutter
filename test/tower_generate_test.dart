import 'package:avidus_product/features/pms/screens/tower_generate_screen.dart';
import 'package:avidus_product/features/pms/utils/tower_generate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('example tower body matches the generate request', () {
    final write = towerGenerateBody(
      name: 'Tower A',
      code: 'A',
      basementsText: '1',
      groundFloor: true,
      floorsText: '12',
      terrace: true,
      unitsText: '4',
      unitFromText: '1',
      unitToText: '12',
      unitCategory: '2BHK',
      codePattern: '{floor}{unit:02}{tower}',
      commonAreasText: 'Lobby',
      liftsText: '2',
      staircasesText: '1',
      floorHeightText: '3.2',
      widthText: '40',
      depthText: '22',
    );

    expect(write.isValid, isTrue);
    expect(write.payload, {
      'building': {'name': 'Tower A', 'code': 'A'},
      'basements': 1,
      'ground_floor': true,
      'floors': 12,
      'terrace': true,
      'units_per_floor': 4,
      'unit_floors': {'from': 1, 'to': 12},
      'unit_category': '2BHK',
      'code_pattern': '{floor}{unit:02}{tower}',
      'common_areas': ['Lobby'],
      'lifts': 2,
      'staircases': 1,
      'floor_height': 3.2,
      'footprint': {'width': 40, 'depth': 22},
    });
  });

  test('empty tower omits optional unit, code, and size fields', () {
    final write = towerGenerateBody(
      name: 'Tower B',
      code: '  ',
      basementsText: '',
      groundFloor: true,
      floorsText: '0',
      terrace: false,
      unitsText: '0',
      unitFromText: '1',
      unitToText: '0',
      unitCategory: '2BHK',
      codePattern: towerCodePatternDefault,
      commonAreasText: ' , ',
      liftsText: '0',
      staircasesText: '0',
      floorHeightText: '',
      widthText: '',
      depthText: '',
    );

    expect(write.isValid, isTrue);
    expect(write.payload!['building'], {'name': 'Tower B'});
    expect(write.payload!.containsKey('unit_floors'), isFalse);
    expect(write.payload!.containsKey('unit_category'), isFalse);
    expect(write.payload!.containsKey('code_pattern'), isFalse);
    expect(write.payload!.containsKey('common_areas'), isFalse);
    expect(write.payload!.containsKey('floor_height'), isFalse);
    expect(write.payload!.containsKey('footprint'), isFalse);
  });

  test('ranges and a reversed unit span are rejected', () {
    final write = towerGenerateBody(
      name: '',
      code: 'ABCDEFGHIJKLMNOPQRSTU',
      basementsText: '11',
      groundFloor: true,
      floorsText: '201',
      terrace: false,
      unitsText: '61',
      unitFromText: '8',
      unitToText: '3',
      unitCategory: '',
      codePattern: '',
      commonAreasText: List.filled(21, 'Lobby').join(', '),
      liftsText: '-1',
      staircasesText: 'nope',
      floorHeightText: '0.1',
      widthText: '40',
      depthText: '',
    );

    expect(write.isValid, isFalse);
    expect(write.errors['name'], 'Building name is required');
    expect(write.errors['code'], contains('20'));
    expect(write.errors['basements'], contains('0 and 10'));
    expect(write.errors['floors'], contains('0 and 200'));
    expect(write.errors['units_per_floor'], contains('0 and 60'));
    expect(write.errors['common_areas'], contains('20'));
    expect(write.errors['staircases'], contains('whole number'));
    expect(write.errors['floor_height'], contains('0.5'));
    expect(write.errors['depth'], 'Width and depth are both required');
  });

  test('unit range is checked only when the floor has units', () {
    final write = towerGenerateBody(
      name: 'Tower A',
      code: 'A',
      basementsText: '0',
      groundFloor: true,
      floorsText: '12',
      terrace: false,
      unitsText: '4',
      unitFromText: '8',
      unitToText: '3',
      unitCategory: '',
      codePattern: towerCodePatternDefault,
      commonAreasText: '',
      liftsText: '0',
      staircasesText: '0',
      floorHeightText: '',
      widthText: '',
      depthText: '',
    );

    expect(write.errors['unit_from'], 'From level cannot be above to level');
    expect(write.errors['unit_to'], 'From level cannot be above to level');
  });

  test('default pattern turns floor 5 unit 3 into 503A', () {
    expect(
      applyTowerCodePattern(
        pattern: towerCodePatternDefault,
        level: 5,
        unit: 3,
        towerCode: 'A',
      ),
      '503A',
    );
    expect(
      applyTowerCodePattern(
        pattern: '{floor:02}{unit_letter}',
        level: 5,
        unit: 3,
        towerCode: 'A',
      ),
      '05C',
    );
    expect(
      applyTowerCodePattern(
        pattern: '{floor}{unit:02}',
        level: 0,
        unit: 1,
        towerCode: 'A',
      ),
      'G01',
    );
    expect(
      applyTowerCodePattern(
        pattern: '{floor:02}-{level}',
        level: -2,
        unit: 1,
        towerCode: 'A',
      ),
      'B02--2',
    );
  });

  test('counts read as a summary and clashes block create', () {
    expect(
      towerGenerateSummary({
        'buildings': 1,
        'floors': 7,
        'units': 16,
        'common_areas': 6,
        'cores': 3,
        'total': 33,
      }),
      '33 nodes: 7 floors, 16 units, 6 common areas, 3 cores, 1 building',
    );
    expect(towerGenerateSummary({'total': 1, 'floors': 1}), '1 node: 1 floor');

    final clashes = readTowerClashes([
      {'field': 'building.name', 'value': 'Tower A', 'message': 'Tower A already exists'},
      {'field': 'code', 'value': 'A', 'message': 'Code A is already used'},
    ]);
    expect(clashes, hasLength(2));
    expect(towerClashFieldErrors(clashes)['name'], 'Tower A already exists');
    expect(towerClashFieldErrors(clashes)['code'], 'Code A is already used');

    final warnings = readTowerWarnings([
      'The code pattern has no {unit} token, so units on the same floor get the same code',
    ]);
    expect(warnings.single, contains('{unit}'));
  });

  testWidgets('create stays disabled until a preview has no clashes', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Map<String, dynamic>? previewed;
    Map<String, dynamic>? created;
    var clash = false;

    Future<Object?> preview(Map<String, dynamic> payload) async {
      previewed = payload;
      if (clash) {
        return {
          'preview': true,
          'counts': {'total': 1, 'buildings': 1},
          'warnings': const <String>[],
          'clashes': [
            {'field': 'building.name', 'value': 'Tower A', 'message': 'Tower A already exists'},
          ],
          'tree': const <Map<String, dynamic>>[],
        };
      }
      return {
        'preview': true,
        'counts': {
          'buildings': 1,
          'floors': 7,
          'units': 16,
          'common_areas': 6,
          'cores': 3,
          'total': 33,
        },
        'warnings': [
          'The code pattern has no {unit} token, so units on the same floor get the same code',
        ],
        'clashes': const <Map<String, dynamic>>[],
        'tree': [
          {
            'ref': 'b',
            'type': 'building',
            'name': 'Tower A',
            'code': 'A',
            'children': [
              {
                'ref': 'f1',
                'type': 'floor',
                'name': 'Floor 1',
                'level_number': 1,
                'children': [
                  {
                    'ref': 'f1u1',
                    'type': 'unit',
                    'name': '101A',
                    'code': '101A',
                    'category': '2BHK',
                    'children': <Map<String, dynamic>>[],
                  },
                ],
              },
            ],
          },
        ],
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: TowerGenerateScreen(
          onPreview: preview,
          onCreate: (payload) async {
            created = payload;
            return {'preview': false};
          },
        ),
      ),
    );

    FilledButton createButton() {
      return tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'));
    }

    expect(createButton().onPressed, isNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Preview'));
    await tester.pump();
    expect(previewed, isNull);
    expect(find.text('Building name is required'), findsWidgets);

    await tester.enterText(find.byKey(const Key('tower-name')), 'Tower A');
    await tester.enterText(find.byKey(const Key('tower-code')), 'A');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Preview'));
    await tester.pumpAndSettle();

    expect(previewed?['building'], {'name': 'Tower A', 'code': 'A'});
    expect(previewed?.containsKey('preview'), isFalse);
    expect(
      find.text('33 nodes: 7 floors, 16 units, 6 common areas, 3 cores, 1 building'),
      findsOneWidget,
    );
    expect(find.textContaining('no {unit} token'), findsOneWidget);
    expect(find.text('101A'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Floor 1').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('101A'), findsOneWidget);
    expect(createButton().onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(created?['building'], {'name': 'Tower A', 'code': 'A'});
  });

  testWidgets('a name clash keeps Create off until the tower is previewed again', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var previews = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TowerGenerateScreen(
          onPreview: (_) async {
            previews += 1;
            return {
              'preview': true,
              'counts': {'total': 0},
              'warnings': const <String>[],
              'clashes': [
                {'field': 'building.name', 'value': 'Tower A', 'message': 'Tower A already exists'},
              ],
              'tree': const <Map<String, dynamic>>[],
            };
          },
          onCreate: (_) async => {'preview': false},
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('tower-name')), 'Tower A');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Tower A already exists'), findsWidgets);
    expect(find.text(towerClashHint), findsWidgets);
    final blocked = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'));
    expect(blocked.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('tower-name')), 'Tower B');
    await tester.pump();
    expect(find.text('Tower A already exists'), findsNothing);
    final stale = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'));
    expect(stale.onPressed, isNull);
    expect(previews, 1);
  });
}
