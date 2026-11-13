import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';

class AdminPaymentReviewPage extends StatefulWidget {
  const AdminPaymentReviewPage({super.key});

  @override
  State<AdminPaymentReviewPage> createState() => _AdminPaymentReviewPageState();
}

class _AdminPaymentReviewPageState extends State<AdminPaymentReviewPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _payments = [];
  String _status = 'all';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (append ? _loadingMore || !_hasMore : _loading) return;
    final offset = append ? _nextOffset : 0;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final response = await SupabaseBackend.client.functions.invoke(
        'admin-api',
        body: {
          'action': 'payments.list',
          'status': _status,
          'reference': _searchController.text.trim(),
          'offset': offset,
          'limit': 50,
        },
      );
      if (response.status < 200 ||
          response.status >= 300 ||
          response.data is! Map) {
        throw StateError('Administrator payment records could not be loaded.');
      }
      final rows = (response.data['payments'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        if (append) {
          _payments = [..._payments, ...rows];
        } else {
          _payments = rows;
        }
        _nextOffset = response.data['nextOffset'] is int
            ? response.data['nextOffset'] as int
            : offset + rows.length;
        _hasMore = response.data['hasMore'] == true;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (append) {
          _loadingMore = false;
        } else {
          _error = error.toString();
          _loading = false;
        }
      });
      if (append) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _review(Map<String, dynamic> payment, String decision) async {
    final reasonController = TextEditingController();
    final approved = decision == 'approve';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          approved ? 'Verify and approve payment?' : 'Reject payment?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              approved
                  ? 'Compare the manually entered reference, date/time, and amount with the receipt. Then verify the transaction against authorized GCash merchant or provider records.'
                  : 'Enter the reason the customer will see.',
            ),
            if (!approved) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Rejection reason',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!approved && reasonController.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: Text(
              approved ? 'Verified in provider records' : 'Reject payment',
            ),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      reasonController.dispose();
      return;
    }
    try {
      final response = await SupabaseBackend.client.functions.invoke(
        'admin-api',
        body: {
          'action': 'payments.review',
          'payment_request_id': payment['id'],
          'decision': decision,
          'confirm_received': approved,
          'review_notes': reasonController.text.trim(),
        },
      );
      if (response.status < 200 || response.status >= 300) {
        throw StateError('Payment review was rejected by the server.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approved ? 'Payment approved.' : 'Payment rejected.'),
          ),
        );
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _showReceipt(String? url) async {
    if (url == null || url.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('The private receipt could not be loaded.'),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payments = _payments;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GCash payment review'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search reference number',
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: Icon(Icons.arrow_forward),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _loading ? null : () => _load(),
                    icon: const Icon(Icons.search),
                    label: const Text('Search'),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Payment status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('All submissions'),
                    ),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text('Approved'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _status = value ?? 'all');
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                if (payments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No matching submissions.')),
                  ),
                for (final payment in payments) _paymentCard(payment),
                if (_hasMore)
                  Center(
                    child: TextButton(
                      onPressed: _loadingMore
                          ? null
                          : () => _load(append: true),
                      child: Text(
                        _loadingMore ? 'Loading…' : 'Load more submissions',
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _paymentCard(Map<String, dynamic> payment) {
    final profile = payment['profile'] is Map
        ? payment['profile'] as Map
        : const {};
    final name =
        payment['customer_full_name'] as String? ??
        profile['display_name'] as String? ??
        'Customer';
    final status = payment['payment_status'] as String? ?? 'pending';
    final date = payment['payment_date'] as String? ?? '—';
    final time = payment['payment_time'] as String? ?? '—';
    final amount = payment['amount_centavos'] as int? ?? 0;
    final plan = payment['payment_plans'] is Map
        ? payment['payment_plans'] as Map
        : const {};
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.green,
              ),
            ),
            Text(payment['customer_email'] as String? ?? 'Email unavailable'),
            const Divider(),
            _detail(
              'Reference',
              payment['merchant_transaction_reference'] as String? ?? '—',
            ),
            _detail('Transaction date / time', '$date · $time'),
            _detail(
              'Amount',
              'PHP ${(amount / 100).toStringAsFixed(2)} · ${plan['name'] ?? ''}',
            ),
            _detail('Submitted', payment['created_at'] as String? ?? '—'),
            _detail(
              'Status',
              status == 'under_review' ? 'PENDING' : status.toUpperCase(),
            ),
            if ((payment['rejection_reason'] as String? ?? '').isNotEmpty)
              _detail(
                'Rejection reason',
                payment['rejection_reason'] as String,
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      _showReceipt(payment['receipt_url'] as String?),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('View full receipt'),
                ),
                if (status == 'under_review') ...[
                  FilledButton(
                    onPressed: () => _review(payment, 'approve'),
                    child: const Text('Approve'),
                  ),
                  TextButton(
                    onPressed: () => _review(payment, 'reject'),
                    child: const Text('Reject'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text('$label: $value'),
  );
}
