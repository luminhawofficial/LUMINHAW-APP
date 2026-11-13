import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/premium_payment_service.dart';
import 'package:luminhaw/features/subscription/premium_payment_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('created payment keeps the customer name and number visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PremiumPaymentPage(paymentProvider: _TestPaymentProvider()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('payment-customer-name')),
      'Sample Grower',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-customer-mobile')),
      '09123456789',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-verified-mobile')),
      '09123456789',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue Premium'));
    await tester.tap(find.text('Continue Premium'));
    await tester.pumpAndSettle();

    expect(find.text('Customer information'), findsOneWidget);
    expect(find.text('Name: Sample Grower'), findsOneWidget);
    expect(find.text('GCash mobile number: 09123456789'), findsOneWidget);
  });

  testWidgets('customer info appears before the QR and selected plan', (
    tester,
  ) async {
    final provider = _TestPaymentProvider();
    await tester.pumpWidget(
      MaterialApp(home: PremiumPaymentPage(paymentProvider: provider)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('payment-customer-name')),
      'Sample Grower',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-customer-mobile')),
      '09123456789',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-verified-mobile')),
      '09123456789',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue Premium'));
    await tester.tap(find.text('Continue Premium'));
    await tester.pumpAndSettle();

    final nameRect = tester.getRect(find.text('Name: Sample Grower'));
    final mobileRect = tester.getRect(
      find.text('GCash mobile number: 09123456789'),
    );
    final qrRect = tester.getRect(
      find.byKey(const ValueKey('gcash-payment-qr')),
    );
    final planRect = tester.getRect(find.text('Selected plan'));

    expect(nameRect.top < mobileRect.top, isTrue);
    expect(mobileRect.top < qrRect.top, isTrue);
    expect(qrRect.top < planRect.top, isTrue);
  });

  testWidgets('customer details are required before continuing', (
    tester,
  ) async {
    final provider = _TestPaymentProvider();
    await tester.pumpWidget(
      MaterialApp(home: PremiumPaymentPage(paymentProvider: provider)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Continue Premium'));
    await tester.tap(find.text('Continue Premium'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your full name.'), findsOneWidget);
    expect(
      find.text('Enter a valid Philippine mobile number.'),
      findsOneWidget,
    );
    expect(find.text('Re-enter your GCash number.'), findsOneWidget);
    expect(provider.createPaymentCallCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a mismatched GCash number blocks payment creation', (
    tester,
  ) async {
    final provider = _TestPaymentProvider();
    await tester.pumpWidget(
      MaterialApp(home: PremiumPaymentPage(paymentProvider: provider)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('payment-customer-name')),
      'Sample Grower',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-customer-mobile')),
      '09123456789',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-verified-mobile')),
      '09123456780',
    );
    await tester.ensureVisible(find.text('Continue Premium'));
    await tester.tap(find.text('Continue Premium'));
    await tester.pumpAndSettle();

    expect(find.text('The GCash mobile numbers do not match.'), findsOneWidget);
    expect(provider.createPaymentCallCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('yearly plan displays its configured GCash QR code', (
    tester,
  ) async {
    final provider = _TestPaymentProvider();
    await tester.pumpWidget(
      MaterialApp(home: PremiumPaymentPage(paymentProvider: provider)),
    );
    await tester.pumpAndSettle();

    final planSelector = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(planSelector);
    await tester.tap(planSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Premium 365 Days · PHP 499.00 / 365 days'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-customer-name')),
      'Sample Grower',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-customer-mobile')),
      '09123456789',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-verified-mobile')),
      '09123456789',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue Premium'));
    await tester.tap(find.text('Continue Premium'));
    await tester.pumpAndSettle();

    final qrImage = tester.widget<Image>(
      find.byKey(const ValueKey('gcash-payment-qr')),
    );
    expect(
      (qrImage.image as NetworkImage).url,
      'https://example.test/gcash-yearly-qr.png',
    );
    expect(find.text('PHP 499.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestPaymentProvider implements PremiumPaymentProvider {
  int createPaymentCallCount = 0;

  @override
  String get method => 'manual_gcash';

  @override
  Future<PremiumPaymentOptions> loadOptions() async =>
      const PremiumPaymentOptions(
        userId: 'test-user',
        enabled: true,
        merchantName: 'Test Merchant',
        merchantRecipient: '+639000000000',
        paymentSteps: 'Pay using GCash.',
        plans: [
          PremiumPaymentPlan(
            code: 'premium_30_days',
            name: 'Premium 30 Days',
            description: 'Monthly access',
            amountCentavos: 4900,
            currency: 'PHP',
            durationDays: 30,
            qrImageUrl: 'https://example.test/gcash-qr.png',
          ),
          PremiumPaymentPlan(
            code: 'premium_365_days',
            name: 'Premium 365 Days',
            description: 'Yearly access',
            amountCentavos: 49900,
            currency: 'PHP',
            durationDays: 365,
            qrImageUrl: 'https://example.test/gcash-yearly-qr.png',
          ),
        ],
        payments: [],
        premiumExpiresAt: null,
      );

  @override
  Future<Map<String, dynamic>> createPayment(
    String planCode, {
    required String fullName,
    required String mobileNumber,
  }) async {
    createPaymentCallCount++;
    final amount = planCode == 'premium_365_days' ? 49900 : 4900;
    return {
      'payment': {
        'id': 'test-request',
        'unique_payment_reference': 'LUM-test-reference',
        'payment_status': 'pending',
        'amount_centavos': amount,
        'currency': 'PHP',
      },
    };
  }

  @override
  Future<void> cancelPendingPayment(String requestId) async {}

  @override
  Future<Map<String, dynamic>> submitPayment({
    required String requestId,
    required String transactionReference,
    required DateTime paymentDate,
    required String? paymentTime,
    required int amountCentavos,
    required Uint8List proofBytes,
    required String proofFileName,
    required String contentType,
  }) async => {};
}
