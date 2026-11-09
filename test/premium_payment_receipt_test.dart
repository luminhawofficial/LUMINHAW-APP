import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/features/subscription/premium_payment_page.dart';

void main() {
  testWidgets('temporary payment receipt fits a narrow mobile viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TemporaryPaymentReceiptDialog(
            planName: 'Premium 30 Days',
            amount: 'PHP 49.00',
            transactionReference: '1234 567 890123',
            paymentDate: DateTime(2026, 11, 9, 10, 30),
            receiptImage: Uint8List.fromList(
              base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/rWQAAAAASUVORK5CYII=',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Temporary payment receipt'), findsOneWidget);
    expect(find.text('Plan: Premium 30 Days'), findsOneWidget);
    expect(find.text('Amount: PHP 49.00'), findsOneWidget);
    expect(find.text('GCash reference: 1234 567 890123'), findsOneWidget);
    expect(find.textContaining('not an official receipt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
