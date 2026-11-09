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
          'amount_centavos': 149900,
          'currency': 'PHP',
          'duration_days': 365,
          'qr_storage_path': 'plans/GCash-MyQR-1499.PNG.jpg',
          'qrImageUrl': 'https://project.supabase.co/storage/v1/object/sign/gcash-payment-assets/plans/GCash-MyQR-1499.PNG.jpg?token=yearly-token',
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
          'entitlement_expires_at': '2026-11-29T00:00:00Z',
          'payment_plans': {
            'code': 'premium_30_days',
            'name': 'Premium 30 Days',
          },
        },
      ],
      'entitlement': {'expires_at': '2026-11-29T00:00:00Z'},
    });

    expect(options.enabled, isTrue);
    expect(options.merchantName, 'Approved merchant');
    expect(options.merchantRecipient, 'Merchant account');
    expect(options.plans.first.qrStoragePath, 'plans/GCash-MyQR-49.PNG.jpg');
    expect(options.plans.first.qrImageUrl, contains('/object/sign/'));
    expect(options.plans.first.qrImageUrl, contains('monthly-token'));
    expect(options.plans.last.amountCentavos, 149900);
    expect(options.plans.last.qrStoragePath, 'plans/GCash-MyQR-1499.PNG.jpg');
    expect(options.plans.last.qrImageUrl, contains('/object/sign/'));
    expect(options.plans.last.qrImageUrl, contains('yearly-token'));
    expect(options.plans.first.amountCentavos, 4900);
    expect(options.payments.single.status, 'approved');
    expect(options.payments.single.planCode, 'premium_30_days');
    expect(
      options.payments.single.entitlementExpiresAt,
      DateTime.parse('2026-11-29T00:00:00Z'),
    );
    expect(options.premiumExpiresAt, DateTime.parse('2026-11-29T00:00:00Z'));
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
        'receipt_validation_manual_review_unsupported',
      ),
      contains('manual review'),
    );
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
      PremiumPaymentService.messageForErrorCode('reference_mismatch'),
      contains('does not match'),
    );
    expect(
      PremiumPaymentService.messageForErrorCode('wrong_payment_amount'),
      contains('does not match'),
    );
    expect(
      PremiumPaymentService.messageForErrorCode('receipt_blurry'),
      'The receipt is blurry or the transaction details cannot be read clearly. Please take a clear, well-lit photo of the receipt, or send it to luminhawofficial@gmail.com for assistance.',
    );
    expect(
      PremiumPaymentService.messageForErrorCode('not_a_receipt'),
      'The uploaded image does not appear to be a GCash receipt. Please upload or take a clear picture of your official GCash receipt.',
    );
  });
}
