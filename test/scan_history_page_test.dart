import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/scan_history_service.dart';
import 'package:luminhaw/features/scanner/scan_history_page.dart';

void main() {
  testWidgets('shows scan names and opens the plant details', (tester) async {
    final record = ScanHistoryRecord(
      id: 'scan-1',
      status: 'completed',
      createdAt: DateTime.utc(2026, 10, 27, 2),
      plantName: 'Mangifera indica',
      commonName: 'Mango',
      family: 'Anacardiaceae',
      probability: 0.94,
      tagalogName: 'Mangga',
      bisayaName: 'Mangga',
      provider: 'plant.id',
      taxonomy: const {'genus': 'Mangifera'},
      plantDetails: const {'soilCompatibility': 'Well-drained soil'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScanHistoryPage(loadHistory: () async => [record]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mango'), findsOneWidget);
    expect(find.text('Mangifera indica'), findsWidgets);
    expect(find.textContaining('Family: Anacardiaceae'), findsOneWidget);
    expect(find.textContaining('Provider score: 94%'), findsOneWidget);

    await tester.tap(find.text('View plant details'));
    await tester.pumpAndSettle();

    expect(find.text('Tagalog name'), findsOneWidget);
    expect(find.text('Mangga'), findsWidgets);
    expect(find.text('Identification provider'), findsOneWidget);
    expect(find.text('Provider match score'), findsOneWidget);
    expect(find.text('Well-drained soil'), findsOneWidget);
    expect(find.text('Genus'), findsOneWidget);
  });

  testWidgets('confirms deletion before removing a scan', (tester) async {
    final record = ScanHistoryRecord(
      id: 'scan-delete',
      status: 'completed',
      createdAt: DateTime.utc(2026, 10, 27, 2),
      plantName: 'Mangifera indica',
      commonName: 'Mango',
    );
    var records = [record];
    String? deletedId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScanHistoryPage(
            loadHistory: () async => records,
            deleteScan: (id) async {
              deletedId = id;
              records = [];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete scan'));
    await tester.pumpAndSettle();
    expect(find.text('Delete scan history?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deletedId, isNull);
    expect(find.text('Mango'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deletedId, 'scan-delete');
    expect(find.text('Mango'), findsNothing);
    expect(find.text('Scan removed from history.'), findsOneWidget);
  });
}
