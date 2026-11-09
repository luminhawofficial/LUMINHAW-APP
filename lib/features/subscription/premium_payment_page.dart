import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/premium_payment_service.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class _GcashReferenceFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!RegExp(r'^[0-9 ]*$').hasMatch(newValue.text)) return oldValue;
    final digits = newValue.text.replaceAll(' ', '');
    if (digits.length > 13) return oldValue;
    final selectionOffset = newValue.selection.extentOffset
        .clamp(0, newValue.text.length)
        .toInt();
    final digitsBeforeCursor = newValue.text
        .substring(0, selectionOffset)
        .replaceAll(' ', '')
        .length;
    final groups = <String>[];
    if (digits.isNotEmpty) {
      groups.add(digits.substring(0, digits.length < 4 ? digits.length : 4));
    }
    if (digits.length > 4) {
      groups.add(digits.substring(4, digits.length < 7 ? digits.length : 7));
    }
    if (digits.length > 7) groups.add(digits.substring(7));
    final formatted = groups.join(' ');
    final cursor =
        digitsBeforeCursor +
        (digitsBeforeCursor > 4 ? 1 : 0) +
        (digitsBeforeCursor > 7 ? 1 : 0);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: cursor.clamp(0, formatted.length).toInt(),
      ),
    );
  }
}

class PremiumPaymentPage extends StatefulWidget {
  const PremiumPaymentPage({super.key});

  @override
  State<PremiumPaymentPage> createState() => _PremiumPaymentPageState();
}

class _PremiumPaymentPageState extends State<PremiumPaymentPage> {
  final PremiumPaymentProvider _paymentProvider =
      const ManualGcashPaymentProvider();
  final _picker = ImagePicker();
  final _transactionReference = TextEditingController();
  final _fullName = TextEditingController();
  final _mobileNumber = TextEditingController();
  PremiumPaymentOptions? _options;
  Map<String, dynamic>? _openRequest;
  XFile? _proof;
  Uint8List? _proofPreviewBytes;
  String? _submissionError;
  DateTime _paymentDate = DateTime.now();
  Object? _loadError;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isChangingPlan = false;
  String? _selectedPlanCode;

  @override
  void initState() {
    super.initState();
    _fullName.text = SupabaseAuthService.displayName ?? '';
    _load();
  }

  @override
  void dispose() {
    _transactionReference.dispose();
    _fullName.dispose();
    _mobileNumber.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final options = await _paymentProvider.loadOptions();
      if (!mounted) return;
      PlanEntitlementStore.instance.applyVerifiedServerSnapshot(
        userId: options.userId,
        expiresAt: options.premiumExpiresAt,
      );
      final pendingPayments = options.payments
          .where(
            (payment) =>
                payment.status == 'pending' || payment.status == 'under_review',
          )
          .toList(growable: false);
      final existing = pendingPayments.isEmpty ? null : pendingPayments.first;
      setState(() {
        _options = options;
        _openRequest = existing == null
            ? null
            : {
                'id': existing.id,
                'unique_payment_reference': existing.reference,
                'payment_status': existing.status,
                'amount_centavos': existing.amountCentavos,
                'currency': existing.currency,
                'plan_code': existing.planCode,
                'payment_plans': {
                  'code': existing.planCode,
                  'name': existing.planName,
                },
              };
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _createPayment(PremiumPaymentPlan plan) async {
    final mobile = _mobileNumber.text.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (_fullName.text.trim().length < 2 ||
        !RegExp(r'^(09\d{9}|\+639\d{9}|639\d{9})$').hasMatch(mobile)) {
      _showMessage(
        'Enter your full name and a valid Philippine mobile number.',
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final result = await _paymentProvider.createPayment(
        plan.code,
        fullName: _fullName.text,
        mobileNumber: mobile,
      );
      if (!mounted) return;
      final payment = result['payment'];
      if (payment is! Map) {
        throw const FormatException('The payment response was incomplete.');
      }
      setState(() {
        _openRequest = {
          ...Map<String, dynamic>.from(payment),
          'plan_code': plan.code,
          'payment_plans': {'code': plan.code, 'name': plan.name},
        };
        _isSubmitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showMessage(error.toString());
      await _load();
    }
  }

  Future<void> _pickProof(ImageSource source) async {
    try {
      final selected = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (selected != null) {
        final bytes = await selected.readAsBytes();
        if (bytes.isEmpty ||
            bytes.length > PremiumPaymentService.maximumProofBytes) {
          if (mounted) {
            _showMessage('Choose a non-empty image no larger than 5 MB.');
          }
          return;
        }
        if (mounted) {
          setState(() {
            _proof = selected;
            _proofPreviewBytes = bytes;
            _submissionError = null;
          });
        }
      }
    } on PlatformException {
      if (mounted) _showMessage('Could not access the selected image.');
    }
  }

  Future<void> _choosePaymentDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: today.subtract(const Duration(days: 90)),
      lastDate: today,
    );
    if (selected != null && mounted) setState(() => _paymentDate = selected);
  }

  Future<void> _choosePaymentTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_paymentDate),
    );
    if (selected != null && mounted) {
      setState(() {
        _paymentDate = DateTime(
          _paymentDate.year,
          _paymentDate.month,
          _paymentDate.day,
          selected.hour,
          selected.minute,
        );
      });
    }
  }

  Future<void> _submitPayment() async {
    final request = _openRequest;
    final reference = _transactionReference.text.trim();
    if (request == null ||
        !RegExp(r'^\d{4} \d{3} \d{6}$').hasMatch(reference)) {
      _showMessage(
        'Your reference number must contain exactly 13 digits in the format 0000 000 000000.',
      );
      return;
    }
    if (_proof == null) {
      _showMessage(
        'Upload your GCash receipt or take a picture of your receipt.',
      );
      return;
    }
    setState(() {
      _isSubmitting = true;
      _submissionError = null;
    });
    try {
      final result = await _paymentProvider.submitPayment(
        requestId: request['id'] as String,
        transactionReference: reference,
        paymentDate: _paymentDate,
        proof: _proof!,
      );
      if (!mounted) return;
      _transactionReference.clear();
      setState(() {
        _proof = null;
        _proofPreviewBytes = null;
        _isSubmitting = false;
        _openRequest = null;
      });
      _showMessage(
        result['message'] is String ? result['message'] as String : 'Your GCash receipt has passed validation. Your payment is now waiting for email verification.',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submissionError = error.toString();
      });
      _showMessage(error.toString());
    }
  }

  Future<void> _changePlan() async {
    final request = _openRequest;
    if (request == null || request['payment_status'] != 'pending') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Premium plan?'),
        content: const Text(
          'This will cancel your pending request and let you choose another plan. Only continue if you have not sent the GCash payment. If you have already paid, do not cancel; contact support for help.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep current plan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isChangingPlan = true);
    try {
      await _paymentProvider.cancelPendingPayment(request['id'] as String);
      if (!mounted) return;
      _transactionReference.clear();
      setState(() {
        _openRequest = null;
        _proof = null;
        _proofPreviewBytes = null;
        _submissionError = null;
        _isChangingPlan = false;
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isChangingPlan = false);
      _showMessage(error.toString());
      await _load();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => ScreenBody(
    title: 'More room to grow',
    subtitle: 'Unlock premium features and give your plants the best care.',
    back: true,
    child: _isLoading
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(color: AppColors.green),
            ),
          )
        : _loadError != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SetupNotice(message: _loadError.toString()),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          )
        : _buildContent(_options!),
  );

  Widget _buildContent(PremiumPaymentOptions options) {
    final current = PlanEntitlementStore.instance.tier.value;
    final readinessMessage = options.readinessIssues.isEmpty
        ? 'Checkout is disabled or this payment status response did not include readiness details. Do not send payment. Try again later or check the local Supabase function and database configuration.'
        : options.readinessIssues
              .map(PremiumPaymentService.messageForReadinessIssue)
              .toSet()
              .join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF4D9E4),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium, color: Color(0xFFB63F6D), size: 16),
              SizedBox(width: 6),
              Text(
                'PREMIUM PLAN',
                style: TextStyle(
                  color: Color(0xFF9B315A),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Image.asset(
            'assets/images/plants/plant_1.png',
            width: 112,
            height: 108,
            fit: BoxFit.contain,
          ),
        ),
        if (current == PlanTier.premium)
          AppCard(
            child: Text(
              options.premiumExpiresAt == null
                  ? 'Your verified Premium entitlement is active.'
                  : 'Premium is active until ${_dateLabel(options.premiumExpiresAt!)}.',
              style: const TextStyle(color: AppColors.green),
            ),
          ),
        if (_openRequest != null && options.enabled) ...[
          _paymentInstructions(options),
          if (_openRequest!['payment_status'] == 'pending') _submissionForm(),
          if (_openRequest!['payment_status'] == 'under_review')
            const SetupNotice(
              message: 'Your payment has been submitted and is waiting for email verification. Premium remains inactive until the GCash transaction is verified.',
            ),
        ] else if (!options.enabled || options.plans.isEmpty) ...[
          SetupNotice(message: readinessMessage),
        ] else ...[
          _customerInformation(),
          const SizedBox(height: 12),
          _checkoutCard(options),
        ],
        const SizedBox(height: 16),
        const Text(
          'Payment history',
          style: TextStyle(
            color: AppColors.green,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (options.payments.isEmpty)
          const Text(
            'No payment requests yet.',
            style: TextStyle(color: AppColors.muted),
          )
        else
          for (final payment in options.payments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment.planName,
                      style: const TextStyle(
                        color: AppColors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_money(payment.amountCentavos, payment.currency)} · ${_statusLabel(payment.status)}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    Text(
                      'Created ${_dateLabel(payment.createdAt)}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    if (payment.entitlementExpiresAt != null)
                      Text(
                        'Premium expires: ${_dateLabel(payment.entitlementExpiresAt!)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    if (payment.reviewNotes != null &&
                        payment.reviewNotes!.isNotEmpty)
                      Text(
                        'Review note: ${payment.reviewNotes}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh status'),
          ),
        ),
      ],
    );
  }

  Widget _checkoutCard(PremiumPaymentOptions options) {
    final selectedPlan = options.plans.firstWhere(
      (plan) => plan.code == _selectedPlanCode,
      orElse: () => options.plans.first,
    );

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Subscription price',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: selectedPlan.code,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              for (final plan in options.plans)
                DropdownMenuItem(
                  value: plan.code,
                  child: Text(
                    '${plan.name} · ${_money(plan.amountCentavos, plan.currency)} / ${plan.durationDays} days',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _isSubmitting
                ? null
                : (code) {
                    if (code != null) {
                      setState(() => _selectedPlanCode = code);
                    }
                  },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: Color(0xFFD4E3D8)),
          ),
          const Text(
            'Payment method',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: 'gcash',
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(
                value: 'gcash',
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 20),
                    SizedBox(width: 10),
                    Text('Manual GCash'),
                  ],
                ),
              ),
            ],
            onChanged: _isSubmitting ? null : (_) {},
          ),
          const SizedBox(height: 8),
          const Text(
            'You will receive the GCash payment instructions next. Premium activates only after your payment is verified.',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () => _createPayment(selectedPlan),
              icon: const Icon(Icons.north_east),
              label: Text(
                _isSubmitting ? 'Preparing payment...' : 'Continue Premium',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text(
                'Return to Free',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentInstructions(PremiumPaymentOptions options) {
    final request = _openRequest!;
    final plan = request['payment_plans'];
    final planName = plan is Map ? plan['name'] as String? : null;
    final planCode =
        request['plan_code'] ?? (plan is Map ? plan['code'] : null);
    final matchingPlans = planCode is String
        ? options.plans.where((item) => item.code == planCode)
        : const <PremiumPaymentPlan>[];
    final selectedPlan = matchingPlans.isEmpty ? null : matchingPlans.first;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GCash payment',
            style: TextStyle(
              color: AppColors.green,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F8EF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  planName ?? 'Premium plan',
                  style: const TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _money(
                    request['amount_centavos'] as int,
                    request['currency'] as String,
                  ),
                  style: const TextStyle(
                    color: AppColors.green,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Payment method: Manual GCash',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          if (options.merchantName != null)
            Text('Merchant: ${options.merchantName}'),
          if (options.merchantRecipient != null)
            Row(
              children: [
                Expanded(
                  child: Text('Recipient: ${options.merchantRecipient}'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: options.merchantRecipient!),
                    );
                    if (mounted) _showMessage('GCash number copied.');
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
              ],
            ),
          if (options.paymentSteps != null) ...[
            const SizedBox(height: 8),
            Text(options.paymentSteps!),
          ],
          if (selectedPlan?.qrImageUrl != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Image.network(
                selectedPlan!.qrImageUrl!,
                width: 220,
                height: 220,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SetupNotice(
                  message: 'The configured GCash QR image is unavailable. Do not send payment until it is restored.',
                ),
              ),
            ),
          ],
          if (request['payment_status'] == 'pending') ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isChangingPlan || _isSubmitting
                    ? null
                    : _changePlan,
                child: Text(
                  _isChangingPlan ? 'Changing plan...' : 'Change plan',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _submissionForm() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload your GCash receipt or take a picture of your receipt.',
            style: TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Make sure the photo is clear, readable, and shows the full Reference No.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _transactionReference,
            maxLength: 15,
            keyboardType: TextInputType.number,
            inputFormatters: [_GcashReferenceFormatter()],
            decoration: const InputDecoration(
              labelText: 'GCash reference number',
              hintText: '0000 000 000000',
              border: OutlineInputBorder(),
            ),
          ),
          TextButton.icon(
            onPressed: _isSubmitting ? null : _choosePaymentDate,
            icon: const Icon(Icons.calendar_today),
            label: Text('Payment date: ${_dateLabel(_paymentDate)}'),
          ),
          TextButton.icon(
            onPressed: _isSubmitting ? null : _choosePaymentTime,
            icon: const Icon(Icons.access_time),
            label: Text('Payment time: ${_timeLabel(_paymentDate)}'),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _pickProof(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take photo'),
              ),
              TextButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _pickProof(ImageSource.gallery),
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  _proof == null ? 'Choose receipt' : 'Replace receipt',
                ),
              ),
            ],
          ),
          if (_proofPreviewBytes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _proofPreviewBytes!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          if (_proof != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => setState(() {
                        _proof = null;
                        _proofPreviewBytes = null;
                      }),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove receipt'),
              ),
            ),
          if (_isSubmitting)
            const LinearProgressIndicator(color: AppColors.green),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting || _isChangingPlan
                  ? null
                  : _submitPayment,
              child: const Text('Verify Payment & Subscribe'),
            ),
          ),
          if (_submissionError != null) ...[
            const SizedBox(height: 8),
            Text(
              _submissionError!,
              style: const TextStyle(color: Color(0xFFB3261E)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Need help? Email your receipt to luminhawofficial@gmail.com.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
          const Text(
            'Receipt validation does not confirm that money was received. Premium activates only after the actual GCash transaction is verified through the email approval link.',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    ),
  );

  Widget _customerInformation() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer information',
          style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _fullName,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Full name',
            border: OutlineInputBorder(),
          ),
        ),
        TextField(
          controller: _mobileNumber,
          keyboardType: TextInputType.phone,
          maxLength: 20,
          decoration: const InputDecoration(
            labelText: 'GCash registered mobile number',
            hintText: '09XXXXXXXXX',
            border: OutlineInputBorder(),
          ),
        ),
        Text(
          'Account email: ${SupabaseAuthService.currentUser?.email ?? 'Unavailable'}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    ),
  );

  static String _money(int amountCentavos, String currency) =>
      '$currency ${(amountCentavos / 100).toStringAsFixed(2)}';

  static String _dateLabel(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _timeLabel(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static String _statusLabel(String status) => switch (status) {
    'pending' || 'under_review' =>
      'Your payment has been submitted and is waiting for verification.',
    'approved' => 'Your payment has been verified. Your Premium subscription is now active.',
    'rejected' => 'Your payment was not approved.',
    'cancelled' => 'Cancelled',
    'expired' => 'Expired',
    _ => 'Unknown',
  };
}
