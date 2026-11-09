import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:luminhaw/features/subscription/premium_payment_page.dart';

class PremiumPage extends StatelessWidget {
  const PremiumPage({super.key});

  static const _freeBenefits = [
    'Identify plants',
    'Explore the plant library',
    'Save plant details',
  ];

  static const _premiumBenefits = [
    'Advanced plant biology',
    'Nutrient information',
    'Plant health diagnosis',
    'Detailed care guides',
    'Plant growth tracking',
    'Unlimited AI assistant access',
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlanTier>(
      valueListenable: PlanEntitlementStore.instance.tier,
      builder: (context, currentTier, _) {
        final isPremium = currentTier == PlanTier.premium;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                const AppHeader(back: true),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Unlock more with LUMINHAW Premium',
                                        style: TextStyle(
                                          color: AppColors.green,
                                          fontFamily: 'PlayfairDisplay',
                                          fontSize: 24,
                                          height: 1.15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        isPremium
                                            ? 'Your Premium entitlement is active.'
                                            : 'Grow with smarter tools and personalized plant care.',
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Image.asset(
                                  'assets/images/plants/plant_4.png',
                                  width: 112,
                                  height: 128,
                                  fit: BoxFit.contain,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _PlanCard(
                              logo: 'assets/images/Free_logo .png',
                              name: 'FREE',
                              price: 'Free',
                              description: 'Essential tools to get started',
                              benefits: _freeBenefits,
                              selected: !isPremium,
                            ),
                            const SizedBox(height: 14),
                            _PlanCard(
                              logo: 'assets/images/Premium_logo .png',
                              name: 'PRO',
                              price: 'PHP 49 / 30 days',
                              description: 'PHP 1,499 / 365 days',
                              benefits: _premiumBenefits,
                              selected: isPremium,
                              premium: true,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: isPremium
                                    ? null
                                    : () => Navigator.pushNamed(
                                        context,
                                        '/payment',
                                      ),
                                child: Text(
                                  isPremium
                                      ? 'Premium active'
                                      : 'Subscribe Now',
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Row(
                              children: [
                                Expanded(
                                  child: _TrustItem(
                                    icon: Icons.lock_outline,
                                    label: 'Secure payment',
                                  ),
                                ),
                                Expanded(
                                  child: _TrustItem(
                                    icon: Icons.event_available_outlined,
                                    label: 'Cancel anytime',
                                  ),
                                ),
                                Expanded(
                                  child: _TrustItem(
                                    icon: Icons.support_agent,
                                    label: 'Support',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const _EntitlementUnavailableNotice(),
                            const SizedBox(height: 10),
                            const SetupNotice(
                              message: 'Manual GCash payments require approved merchant details, private QR codes, receipt validation, and email review. Payments remain unavailable until configured.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.logo,
    required this.name,
    required this.price,
    required this.description,
    required this.benefits,
    required this.selected,
    this.premium = false,
  });

  final String logo;
  final String name;
  final String price;
  final String description;
  final List<String> benefits;
  final bool selected;
  final bool premium;

  @override
  Widget build(BuildContext context) {
    final foreground = premium ? Colors.white : AppColors.green;
    final secondary = premium ? Colors.white70 : AppColors.muted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: premium ? AppColors.green : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: selected && !premium
            ? Border.all(color: AppColors.green, width: 1.5)
            : null,
        boxShadow: const [
          BoxShadow(
            color: Color(0x120B5E48),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(logo, width: 42, height: 42, fit: BoxFit.contain),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Text(
                price,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Text(
              description,
              style: TextStyle(color: secondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          for (final benefit in benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle,
                    color: premium ? Colors.white : AppColors.green,
                    size: 17,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      benefit,
                      style: TextStyle(color: foreground, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: AppColors.green, size: 20),
      const SizedBox(height: 4),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted, fontSize: 10),
      ),
    ],
  );
}

class PaymentPage extends StatelessWidget {
  const PaymentPage({super.key});

  @override
  Widget build(BuildContext context) => const PremiumPaymentPage();
}

class _EntitlementUnavailableNotice extends StatelessWidget {
  const _EntitlementUnavailableNotice();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Object?>(
    valueListenable: PlanEntitlementStore.instance.refreshError,
    builder: (context, error, _) => error == null
        ? const SizedBox.shrink()
        : const SetupNotice(
            message: 'Your subscription status could not be verified. Premium features remain locked until the account service is available.',
          ),
  );
}
