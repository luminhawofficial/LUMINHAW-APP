import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class PremiumPaymentPlan {
  const PremiumPaymentPlan({
    required this.code,
    required this.name,
    required this.description,
    required this.amountCentavos,
    required this.currency,
    required this.durationDays,
    this.qrImageUrl,
    this.qrStoragePath,
  });

  final String code;
  final String name;
  final String description;
  final int amountCentavos;
  final String currency;
  final int durationDays;
  final String? qrImageUrl;
  final String? qrStoragePath;

  factory PremiumPaymentPlan.fromJson(Map<String, dynamic> json) {
    final code = json['code'];
    final name = json['name'];
    final amount = json['amount_centavos'];
    final currency = json['currency'];
    final days = json['duration_days'];
    if (code is! String ||
        name is! String ||
        amount is! int ||
        currency is! String ||
        days is! int) {
      throw const FormatException('Invalid Premium plan data.');
    }
    return PremiumPaymentPlan(
      code: code,
      name: name,
      description: json['description'] is String
          ? json['description'] as String
          : '',
      amountCentavos: amount,
      currency: currency,
      durationDays: days,
      qrImageUrl: json['qrImageUrl'] is String
          ? json['qrImageUrl'] as String
          : null,
      qrStoragePath: json['qr_storage_path'] is String
          ? json['qr_storage_path'] as String
          : null,
    );
  }
}

@immutable
class PremiumPaymentRecord {
  const PremiumPaymentRecord({
    required this.id,
    required this.reference,
    required this.status,
    required this.amountCentavos,
    required this.currency,
    required this.planName,
    required this.createdAt,
    this.planCode,
    this.transactionReference,
    this.reviewNotes,
    this.entitlementExpiresAt,
  });

  final String id;
  final String reference;
  final String status;
  final int amountCentavos;
  final String currency;
  final String planName;
  final DateTime createdAt;
  final String? planCode;
  final String? transactionReference;
  final String? reviewNotes;
  final DateTime? entitlementExpiresAt;

  factory PremiumPaymentRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final reference = json['unique_payment_reference'];
    final status = json['payment_status'];
    final amount = json['amount_centavos'];
    final currency = json['currency'];
    final date = DateTime.tryParse('${json['created_at']}');
    final plan = json['payment_plans'];
    final planName = plan is Map<String, dynamic> ? plan['name'] : null;
    final planCode = plan is Map<String, dynamic> ? plan['code'] : null;
    if (id is! String ||
        reference is! String ||
        status is! String ||
        amount is! int ||
        currency is! String ||
        date == null ||
        planName is! String) {
      throw const FormatException('Invalid payment history data.');
    }
    return PremiumPaymentRecord(
      id: id,
      reference: reference,
      status: status,
      amountCentavos: amount,
      currency: currency,
      planName: planName,
      createdAt: date,
      planCode: planCode is String ? planCode : null,
      transactionReference: json['merchant_transaction_reference'] as String?,
      reviewNotes: json['review_notes'] as String?,
      entitlementExpiresAt: json['entitlement_expires_at'] is String
          ? DateTime.tryParse(json['entitlement_expires_at'] as String)
          : null,
    );
  }
}

@immutable
class PremiumPaymentOptions {
  const PremiumPaymentOptions({
    required this.userId,
    required this.enabled,
    required this.merchantName,
    required this.merchantRecipient,
    required this.paymentSteps,
    required this.plans,
    required this.payments,
    required this.premiumExpiresAt,
    this.readinessIssues = const [],
  });

  final String userId;
  final bool enabled;
  final String? merchantName;
  final String? merchantRecipient;
  final String? paymentSteps;
  final List<PremiumPaymentPlan> plans;
  final List<PremiumPaymentRecord> payments;
  final DateTime? premiumExpiresAt;
  final List<String> readinessIssues;

  factory PremiumPaymentOptions.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'];
    final userId = json['userId'];
    final plans = json['plans'];
    final payments = json['payments'];
    final readinessIssues = json['readinessIssues'];
    if (enabled is! bool ||
        userId is! String ||
        plans is! List ||
        payments is! List ||
        (readinessIssues != null &&
            (readinessIssues is! List ||
                readinessIssues.any((issue) => issue is! String)))) {
      throw const FormatException('Invalid payment service response.');
    }
    final method = json['paymentMethod'];
    final entitlement = json['entitlement'];
    return PremiumPaymentOptions(
      userId: userId,
      enabled: enabled,
      merchantName: method is Map<String, dynamic>
          ? method['merchantName'] as String?
          : null,
      merchantRecipient: method is Map<String, dynamic>
          ? method['recipient'] as String?
          : null,
      paymentSteps: method is Map<String, dynamic>
          ? method['steps'] as String?
          : null,
      plans: plans
          .map(
            (item) => PremiumPaymentPlan.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      payments: payments
          .map(
            (item) => PremiumPaymentRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      premiumExpiresAt: entitlement is Map<String, dynamic>
          ? DateTime.tryParse('${entitlement['expires_at']}')
          : null,
      readinessIssues: readinessIssues == null
          ? const []
          : List<String>.from(readinessIssues as List),
    );
  }
}

class PremiumPaymentService {
  PremiumPaymentService._();

  static const proofBucket = 'premium-payment-proofs';
  static const maximumProofBytes = 5 * 1024 * 1024;
  static const _allowedProofTypes = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
  };

  static Future<PremiumPaymentOptions> loadOptions() async {
    final payload = await _invoke('get-premium-payment-status', const {});
    return PremiumPaymentOptions.fromJson(payload);
  }

  static Future<Map<String, dynamic>> createPayment(
    String planCode, {
    required String fullName,
    required String mobileNumber,
  }) => _invoke('create-premium-payment', {
    'planCode': planCode,
    'fullName': fullName.trim(),
    'mobileNumber': mobileNumber.trim(),
  });

  static Future<void> cancelPendingPayment(String requestId) async {
    await _invoke('cancel-premium-payment', {'requestId': requestId});
  }

  static Future<Map<String, dynamic>> submitPayment({
    required String requestId,
    required String transactionReference,
    required DateTime paymentDate,
    required XFile proof,
  }) async {
    final userId = SupabaseAuthService.currentUser?.id;
    if (userId == null) {
      throw const PremiumPaymentException('Sign in to submit a payment.');
    }
    final normalizedReference = transactionReference.replaceAll(' ', '');
    if (!RegExp(r'^\d{13}$').hasMatch(normalizedReference)) {
      throw const PremiumPaymentException(
        'Your reference number must contain exactly 13 digits in the format 0000 000 000000.',
      );
    }
    final extension = proof.name.split('.').last.toLowerCase();
    final contentType = _allowedProofTypes[extension];
    if (contentType == null) {
      throw const PremiumPaymentException(
        'Choose a JPEG or PNG payment screenshot.',
      );
    }
    if (proof.mimeType != null && proof.mimeType != contentType) {
      throw const PremiumPaymentException(
        'The screenshot format could not be verified. Select a JPEG or PNG image.',
      );
    }
    final fileLength = await proof.length();
    if (fileLength == 0 || fileLength > maximumProofBytes) {
      throw const PremiumPaymentException(
        'Payment screenshots must be at most 5 MB.',
      );
    }
    final bytes = await proof.readAsBytes();
    if (bytes.length != fileLength || bytes.length > maximumProofBytes) {
      throw const PremiumPaymentException(
        'Payment screenshots must be at most 5 MB.',
      );
    }
    final random = math.Random.secure();
    final fileName =
        '${List<int>.generate(32, (_) => random.nextInt(256)).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}.$extension';
    final proofPath = '$userId/$requestId/$fileName';
    try {
      await SupabaseBackend.client.storage
          .from(proofBucket)
          .uploadBinary(
            proofPath,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
    } on StorageException {
      throw const PremiumPaymentException(
        'The private payment proof upload failed. Try again.',
      );
    } on SocketException {
      throw const PremiumPaymentException(
        'The payment proof could not be uploaded because the network is unavailable.',
      );
    } on TimeoutException {
      throw const PremiumPaymentException(
        'The payment proof upload timed out. Try again.',
      );
    }
    return _invoke('submit-premium-payment', {
      'requestId': requestId,
      'transactionReference': normalizedReference,
      'paymentDate':
          '${paymentDate.year.toString().padLeft(4, '0')}-'
          '${paymentDate.month.toString().padLeft(2, '0')}-'
          '${paymentDate.day.toString().padLeft(2, '0')}',
      'paymentTime':
          '${paymentDate.hour.toString().padLeft(2, '0')}:'
          '${paymentDate.minute.toString().padLeft(2, '0')}',
      'proofStoragePath': proofPath,
    });
  }

  @visibleForTesting
  static String messageForErrorCode(String code) => switch (code) {
    'payment_configuration_missing' => 'Payment function configuration is incomplete. Check the Supabase runtime settings listed in the error.',
    'payment_channel_unavailable' =>
      'GCash payments are currently being configured. Please check back later.',
    'payment_plan_unavailable' =>
      'That Premium plan is not currently available.',
    'payment_request_already_open' => 'You already have an open payment request. Continue or check its status below.',
    'payment_request_not_cancellable' => 'This request can no longer be changed because it has already been submitted or is no longer pending. Refresh to see its latest status.',
    'receipt_validation_unavailable' =>
      'Receipt validation is temporarily unavailable. Please try again later.',
    'receipt_missing' =>
      'Upload your GCash receipt or take a picture of your receipt.',
    'not_a_receipt' => 'The uploaded image does not appear to be a GCash receipt. Please upload or take a clear picture of your official GCash receipt.',
    'not_gcash_receipt' => 'The uploaded image does not appear to be a GCash receipt. Please upload or take a clear picture of your official GCash receipt.',
    'receipt_blurry' => 'The receipt is blurry or the transaction details cannot be read clearly. Please take a clear, well-lit photo of the receipt, or send it to luminhawofficial@gmail.com for assistance.',
    'receipt_unreadable' => 'The receipt is blurry or the transaction details cannot be read clearly. Please take a clear, well-lit photo of the receipt, or send it to luminhawofficial@gmail.com for assistance.',
    'receipt_incomplete' => 'The receipt is blurry or the transaction details cannot be read clearly. Please take a clear, well-lit photo of the receipt, or send it to luminhawofficial@gmail.com for assistance.',
    'reference_invalid' => 'Your reference number must contain exactly 13 digits in the format 0000 000 000000.',
    'reference_mismatch' => 'The reference number you entered does not match the reference found on the receipt. Please check your receipt and correct it.',
    'wrong_payment_amount' =>
      'The payment amount does not match your selected subscription plan.',
    'payment_date_mismatch' =>
      'The transaction date does not match the date on your GCash receipt.',
    'transaction_not_successful' =>
      'The GCash receipt does not show a successful transaction.',
    'duplicate_reference' || 'duplicate_payment_reference' =>
      'This GCash reference number has already been submitted or used.',
    'receipt_validation_inconclusive' => 'The receipt is blurry or the transaction details cannot be read clearly. Please take a clear, well-lit photo of the receipt, or send it to luminhawofficial@gmail.com for assistance.',
    'payment_submission_unavailable' ||
    'payment_status_unavailable' ||
    'payment_service_unavailable' ||
    'payment_review_unavailable' =>
      'The payment service is temporarily unavailable. Please try again later.',
    'invalid_payment_submission' ||
    'invalid_payment_date' ||
    'invalid_customer_mobile' ||
    'invalid_customer_information' =>
      'Check the transaction reference and payment date, then try again.',
    'payment_proof_unavailable' =>
      'The screenshot could not be verified. Please upload it again.',
    'payment_request_not_submittable' => 'This payment request has already been submitted or is no longer available.',
    'invalid_payment_request' =>
      'The payment request could not be identified. Refresh and try again.',
    'invalid_payment_proof_path' =>
      'The payment screenshot path is invalid. Please select the image again.',
    'authentication_required' ||
    'invalid_session' => 'Sign in again with a verified email to continue.',
    'email_verification_required' =>
      'Verify your email address before using Premium payments.',
    'rate_limit_exceeded' =>
      'Too many payment requests. Wait a while and try again.',
    _ => 'The payment request could not be completed. Please try again.',
  };

  static String messageForReadinessIssue(String issue) => switch (issue) {
    'gcash_payments_disabled' =>
      'Checkout is disabled: GCASH_PAYMENTS_ENABLED must be explicitly true.',
    'gcash_merchant_name_missing' =>
      'Set GCASH_MERCHANT_NAME to the approved merchant name.',
    'gcash_merchant_account_missing' =>
      'Set GCASH_MERCHANT_ACCOUNT to the approved receiving account.',
    'gcash_payment_instructions_missing' =>
      'Set GCASH_PAYMENT_INSTRUCTIONS to the approved payment instructions.',
    'resend_api_key_missing' => 'Set RESEND_API_KEY for payment notifications.',
    'resend_sender_missing' =>
      'Set RESEND_FROM_EMAIL (or PREMIUM_EMAIL_FROM) to a verified sender.',
    'supabase_url_missing' =>
      'SUPABASE_URL is missing from the Edge Function runtime.',
    'receipt_validation_not_configured' =>
      'Set OCR_SPACE_API_KEY to configure receipt text extraction.',
    'receipt_validation_manual_review_unsupported' => 'The configured OCR provider cannot safely route receipts without a confidence score to manual review.',
    'monthly_plan_missing' => 'The 30-day Premium plan is missing.',
    'yearly_plan_missing' => 'The 365-day Premium plan is missing.',
    'monthly_plan_disabled' => 'The 30-day Premium plan is disabled.',
    'yearly_plan_disabled' => 'The 365-day Premium plan is disabled.',
    'monthly_plan_configuration_invalid' => 'The 30-day plan must be PHP 49 for 30 days with QR path plans/GCash-MyQR-49.PNG.jpg.',
    'yearly_plan_configuration_invalid' => 'The 365-day plan must be PHP 499 for 365 days with QR path plans/GCash-MyQR-499.PNG.jpg.',
    'monthly_qr_unavailable' => 'The private QR object gcash-payment-assets/plans/GCash-MyQR-49.PNG.jpg is missing or cannot be signed.',
    'yearly_qr_unavailable' => 'The private QR object gcash-payment-assets/plans/GCash-MyQR-499.PNG.jpg is missing or cannot be signed.',
    'unsupported_payment_plan_enabled' =>
      'An unsupported Premium payment plan is enabled.',
    _ => 'A required payment readiness check failed. Do not send payment; please try again later.',
  };

  static Future<Map<String, dynamic>> _invoke(
    String function, [
    Map<String, Object?> body = const {},
  ]) async {
    if (!SupabaseBackend.isInitialized) {
      throw const PremiumPaymentException(
        'Payment services are not configured on this app.',
      );
    }
    final user = SupabaseAuthService.currentUser;
    if (user == null || user.emailConfirmedAt == null) {
      throw const PremiumPaymentException(
        'Sign in with a verified email to use Premium payments.',
      );
    }
    final requestUserId = user.id;
    try {
      final response = await SupabaseBackend.client.functions.invoke(
        function,
        body: body,
      );
      if (SupabaseAuthService.currentUser?.id != requestUserId) {
        throw const PremiumPaymentException(
          'Your account changed while the payment request was in progress. Try again.',
        );
      }
      if (response.status < 200 || response.status >= 300) {
        throw PremiumPaymentException(
          _errorMessage(response.data) ??
              messageForErrorCode(
                _errorCode(response.data) ?? 'payment_service_unavailable',
              ),
        );
      }
      if (response.data is! Map) {
        throw const PremiumPaymentException(
          'The payment service returned an invalid response.',
        );
      }
      return Map<String, dynamic>.from(response.data as Map);
    } on FunctionException catch (error) {
      throw PremiumPaymentException(
        _errorMessage(error.details) ??
            messageForErrorCode(
              _errorCode(error.details) ??
                  (error.status == 429
                      ? 'rate_limit_exceeded'
                      : 'payment_service_unavailable'),
            ),
      );
    } on SocketException {
      throw const PremiumPaymentException(
        'The payment service could not be reached. Check your connection.',
      );
    } on TimeoutException {
      throw const PremiumPaymentException(
        'The payment service timed out. Please try again.',
      );
    }
  }

  static String? _errorCode(Object? data) {
    if (data is Map) {
      if (data['error_code'] is String) return data['error_code'] as String;
      final error = data['error'];
      if (error is Map && error['code'] is String) {
        return error['code'] as String;
      }
    }
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return _errorCode(decoded);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static String? _errorMessage(Object? data) {
    if (data is String) {
      try {
        return _errorMessage(jsonDecode(data));
      } on FormatException {
        return null;
      }
    }
    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        final readinessIssues = error['readinessIssues'];
        if (readinessIssues is List &&
            readinessIssues.isNotEmpty &&
            readinessIssues.every((issue) => issue is String)) {
          return readinessIssues
              .cast<String>()
              .map(messageForReadinessIssue)
              .toSet()
              .join('\n');
        }
      }
      if (data['message'] is String && (data['message'] as String).isNotEmpty) {
        return data['message'] as String;
      }
      if (error is Map &&
          error['message'] is String &&
          (error['message'] as String).isNotEmpty) {
        return error['message'] as String;
      }
    }
    return null;
  }
}

abstract interface class PremiumPaymentProvider {
  String get method;

  Future<PremiumPaymentOptions> loadOptions();

  Future<Map<String, dynamic>> createPayment(
    String planCode, {
    required String fullName,
    required String mobileNumber,
  });

  Future<void> cancelPendingPayment(String requestId);

  Future<Map<String, dynamic>> submitPayment({
    required String requestId,
    required String transactionReference,
    required DateTime paymentDate,
    required XFile proof,
  });
}

class ManualGcashPaymentProvider implements PremiumPaymentProvider {
  const ManualGcashPaymentProvider();

  @override
  String get method => 'manual_gcash';

  @override
  Future<PremiumPaymentOptions> loadOptions() =>
      PremiumPaymentService.loadOptions();

  @override
  Future<Map<String, dynamic>> createPayment(
    String planCode, {
    required String fullName,
    required String mobileNumber,
  }) => PremiumPaymentService.createPayment(
    planCode,
    fullName: fullName,
    mobileNumber: mobileNumber,
  );

  @override
  Future<void> cancelPendingPayment(String requestId) =>
      PremiumPaymentService.cancelPendingPayment(requestId);

  @override
  Future<Map<String, dynamic>> submitPayment({
    required String requestId,
    required String transactionReference,
    required DateTime paymentDate,
    required XFile proof,
  }) => PremiumPaymentService.submitPayment(
    requestId: requestId,
    transactionReference: transactionReference,
    paymentDate: paymentDate,
    proof: proof,
  );
}

class PremiumPaymentException implements Exception {
  const PremiumPaymentException(this.message);

  final String message;

  @override
  String toString() => message;
}
