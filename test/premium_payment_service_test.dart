import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/premium_payment_service.dart';

void main() {
  test('parses server-configured Premium plans without client pricing', () {
    final options = PremiumPaymentOptions.fromJson({
      'userId': 'account-id',
      'enabled': true,
      'paymentMethod': {
        'method': 'manual_gcash',
        'merchantName': 'Approved merchant',
        'recipient': 'Merchant account',
        'steps': 'Use the request reference.',
      },
      'plans': [
        {
          'code': 'premium_30_days',
          'name': 'Premium 30 Days',
          'description': 'Monthly access',
          'amount_centavos': 4900,
          'currency': 'PHP',
          'duration_days': 30,
          'qr_storage_path': 'plans/GCash-MyQR-49.PNG.jpg',
          'qrImageUrl': 'https://project.supabase.co/storage/v1/object/sign/gcash-payment-assets/plans/GCash-MyQR-49.PNG.jpg?token=monthly-token',
        },
        {
          'code': 'premium_365_days',
          'name': 'Premium 365 Days',
          'description': 'Yearly access',
          'amount_centavos': 49900,
          'currency': 'PHP',
          'duration_days': 365,
          'qr_storage_path': 'plans/GCash-MyQR-499.PNG.jpg',
          'qrImageUrl': 'https://project.supabase.co/storage/v1/object/sign/gcash-payment-assets/plans/GCash-MyQR-499.PNG.jpg?token=yearly-token',
        },
      ],
      'payments': [
        {
          'id': 'request-id',
          'unique_payment_reference': 'LUM-payment-reference',
          'payment_status': 'approved',
          'amount_centavos': 4900,
          'currency': 'PHP',
          'created_at': '2026-10-30T00:00:00Z',
          'customer_full_name': 'Sample Grower',
          'customer_mobile_number': '+639123456789',
          'entitlement_expires_at': '2026-11-29T00:00:00Z',
          'payment_plans': {
            'code': 'premium_30_days',
            'name': 'Premium 30 Days',
          },
        },
      ],
      'entitlement': {
        'product_id': 'premium_30_days',
        'status': 'active',
        'verified_at': '2026-10-30T00:00:00Z',
        'expires_at': '2026-11-29T00:00:00Z',
      },
    });

    expect(options.enabled, isTrue);
    expect(options.merchantName, 'Approved merchant');
    expect(options.merchantRecipient, 'Merchant account');
    expect(options.plans.first.qrStoragePath, 'plans/GCash-MyQR-49.PNG.jpg');
    expect(options.plans.first.qrImageUrl, contains('/object/sign/'));
    expect(options.plans.first.qrImageUrl, contains('monthly-token'));
    expect(options.plans.last.amountCentavos, 49900);
    expect(options.plans.last.qrStoragePath, 'plans/GCash-MyQR-499.PNG.jpg');
    expect(options.plans.last.qrImageUrl, contains('/object/sign/'));
    expect(options.plans.last.qrImageUrl, contains('yearly-token'));
    expect(options.plans.first.amountCentavos, 4900);
    expect(options.payments.single.status, 'approved');
    expect(options.payments.single.planCode, 'premium_30_days');
    expect(options.payments.single.customerFullName, 'Sample Grower');
    expect(options.payments.single.customerMobileNumber, '+639123456789');
    expect(
      options.payments.single.entitlementExpiresAt,
      DateTime.parse('2026-11-29T00:00:00Z'),
    );
    expect(options.premiumExpiresAt, DateTime.parse('2026-11-29T00:00:00Z'));
    expect(options.premiumStartsAt, DateTime.parse('2026-10-30T00:00:00Z'));
    expect(options.premiumProductId, 'premium_30_days');
    expect(options.premiumStatus, 'active');
  });

  test('parses disabled payment service without showing sample plans', () {
    final options = PremiumPaymentOptions.fromJson({
      'userId': 'account-id',
      'enabled': false,
      'readinessIssues': ['gcash_payments_disabled', 'monthly_plan_disabled'],
      'paymentMethod': null,
      'plans': [],
      'payments': [],
      'entitlement': null,
    });

    expect(options.enabled, isFalse);
    expect(options.plans, isEmpty);
    expect(options.payments, isEmpty);
    expect(options.readinessIssues, [
      'gcash_payments_disabled',
      'monthly_plan_disabled',
    ]);
    expect(
      PremiumPaymentService.messageForReadinessIssue('monthly_plan_disabled'),
      'The 30-day Premium plan is disabled.',
    );
    expect(
      PremiumPaymentService.messageForReadinessIssue(
        'gcash_merchant_account_missing',
      ),
      contains('GCASH_MERCHANT_ACCOUNT'),
    );
    expect(
      PremiumPaymentService.messageForReadinessIssue('resend_sender_missing'),
      contains('RESEND_FROM_EMAIL'),
    );
    expect(
      PremiumPaymentService.messageForReadinessIssue(
        'resend_test_recipient_missing',
      ),
      'Checkout is unavailable because the test email inbox is not configured. Do not send payment.',
    );
  });

  test('uses the active entitlement returned by payment status', () {
    final options = PremiumPaymentOptions.fromJson({
      'userId': 'account-id',
      'enabled': false,
      'paymentMethod': null,
      'plans': [],
      'payments': [],
      'entitlement': {
        'product_id': 'manual_gcash',
        'status': 'expired',
        'verified_at': '2026-10-01T00:00:00Z',
        'expires_at': '2026-11-01T00:00:00Z',
      },
      'activeEntitlement': {
        'product_id': 'manual_gcash',
        'status': 'active',
        'verified_at': '2026-11-01T00:00:00Z',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 30))
            .toIso8601String(),
      },
    });

    expect(options.premiumStatus, 'active');
    expect(options.premiumExpiresAt, isNotNull);
    expect(options.premiumExpiresAt!.isAfter(DateTime.now().toUtc()), isTrue);
  });

  test('rejects malformed payment service responses', () {
    expect(
      () => PremiumPaymentOptions.fromJson({
        'userId': 'account-id',
        'enabled': true,
        'plans': 'not-an-array',
        'payments': [],
      }),
      throwsFormatException,
    );
  });

  test('maps payment validation errors clearly', () {
    expect(
      PremiumPaymentService.messageForErrorCode('payment_channel_unavailable'),
      contains('GCash payments are currently being configured'),
    );
    expect(
      PremiumPaymentService.messageForErrorCode('payment_request_already_open'),
      contains('open payment request'),
    );
    expect(
      PremiumPaymentService.messageForErrorCode(
        'payment_request_not_cancellable',
      ),
      contains('already been submitted'),
    );
    expect(
      PremiumPaymentService.messageForErrorCode('wrong_payment_amount'),
      contains('does not match'),
    );
    expect(
      PremiumPaymentService.messageForErrorCode('not_a_receipt'),
      'Upload a valid JPG or PNG receipt image, up to 5 MB.',
    );
  });
}
