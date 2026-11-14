import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/features/admin/admin_plant_catalog_page.dart';

void main() {
  testWidgets('plant creation requires sourced names', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminPlantCatalogPage()));

    final form = tester.state<FormState>(find.byType(Form));
    expect(form.validate(), isFalse);
    await tester.pumpAndSettle();

    expect(find.text('Common name is required.'), findsOneWidget);
    expect(find.text('Scientific name is required.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('admin-plant-common_name')),
      'Kangkong',
    );
    await tester.enterText(
      find.byKey(const ValueKey('admin-plant-scientific_name')),
      'Ipomoea aquatica',
    );
    expect(form.validate(), isFalse);
    await tester.pumpAndSettle();

    expect(find.text('Add at least one source URL.'), findsNWidgets(2));

    await tester.enterText(
      find.byKey(const ValueKey('admin-plant-source-common_name')),
      'https://example.org/kangkong',
    );
    await tester.enterText(
      find.byKey(const ValueKey('admin-plant-source-scientific_name')),
      'http://example.org/ipomoea',
    );
    expect(form.validate(), isFalse);
    await tester.pumpAndSettle();

    expect(find.text('Use valid HTTPS source URL(s).'), findsOneWidget);
  });
}
