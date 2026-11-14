import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/widgets/password_policy_field.dart';

void main() {
  testWidgets('shows live requirements and supports password visibility', (
    tester,
  ) async {
    final password = TextEditingController();
    addTearDown(password.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasswordPolicyField(controller: password, label: 'Password'),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'Luminhaw2026');
    await tester.pump();

    expect(find.text('One uppercase letter (A–Z)'), findsOneWidget);
    expect(find.text('One special symbol'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).obscureText,
      isTrue,
    );

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).obscureText,
      isFalse,
    );
  });

  testWidgets('shows matching confirmation as the value changes', (
    tester,
  ) async {
    final password = TextEditingController(text: 'Luminhaw@2026');
    final confirmation = TextEditingController();
    addTearDown(password.dispose);
    addTearDown(confirmation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasswordPolicyField(
            controller: confirmation,
            confirmationOf: password,
            label: 'Confirm password',
          ),
        ),
      ),
    );

    expect(find.text('Enter the same password again'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Luminhaw@2026');
    await tester.pump();
    expect(find.text('Passwords match'), findsOneWidget);
  });
}
