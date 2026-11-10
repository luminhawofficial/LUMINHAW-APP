import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    this.back = false,
    this.onBack,
    this.trailing,
    this.dark = false,
    this.showPlan = true,
    this.showNotifications = true,
    this.backgroundColor,
  });

  final bool back;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool dark;
  final bool showPlan;
  final bool showNotifications;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final foreground = dark ? Colors.white : AppColors.green;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          if (back)
            IconButton(
              onPressed: onBack ?? () => Navigator.maybePop(context),
              icon: Icon(Icons.arrow_back, color: foreground),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          Image.asset('assets/icons/logo.png', width: 24, height: 24),
          const SizedBox(width: 7),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'LUMINHAW',
                style: TextStyle(
                  color: foreground,
                  fontFamily: 'Cinzel',
                  fontWeight: FontWeight.w700,
                  fontVariations: const [FontVariation.weight(700)],
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const Spacer(),
          if (showNotifications)
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => Navigator.pushNamed(context, '/notifications'),
              icon: Icon(Icons.notifications_none, color: foreground),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          const SizedBox(width: 4),
          trailing ?? const SizedBox.shrink(),
          if (showPlan) ...[
            if (trailing != null) const SizedBox(width: 8),
            const PlanBadge(),
          ],
        ],
      ),
    );
  }
}

class PlanBadge extends StatelessWidget {
  const PlanBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlanTier>(
      valueListenable: PlanEntitlementStore.instance.tier,
      builder: (context, tier, _) {
        final isPremium = tier == PlanTier.premium;
        return Tooltip(
          message: isPremium ? 'Premium plan' : 'Basic plan',
          child: InkWell(
            onTap: () => Navigator.pushNamed(context, '/premium'),
            customBorder: const CircleBorder(),
            child: Container(
              width: 38,
              height: 38,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: darkBadgeBackground(isPremium),
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                isPremium
                    ? 'assets/images/Premium_logo .png'
                    : 'assets/images/Free_logo .png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }
}

Color darkBadgeBackground(bool isPremium) =>
    isPremium ? const Color(0xFFFFF2CF) : const Color(0xFFD9EADB);

class ScreenBody extends StatelessWidget {
  const ScreenBody({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.back = false,
    this.trailing,
    this.dark = false,
    this.showPlan = true,
    this.backgroundColor,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool back;
  final Widget? trailing;
  final bool dark;
  final bool showPlan;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          backgroundColor ?? (dark ? AppColors.green : AppColors.background),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              back: back,
              trailing: trailing,
              dark: dark,
              showPlan: showPlan,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: dark ? Colors.white : AppColors.green,
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 28,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: dark ? Colors.white70 : AppColors.muted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    child,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.green.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

class SetupNotice extends StatelessWidget {
  const SetupNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2D8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF8A5A00), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF684600), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumFeatureGate extends StatelessWidget {
  const PremiumFeatureGate({
    super.key,
    required this.feature,
    required this.child,
  });

  final String feature;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlanTier>(
      valueListenable: PlanEntitlementStore.instance.tier,
      builder: (context, tier, _) {
        if (PlanEntitlementStore.instance.hasPremiumAccess) {
          return child;
        }
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD8D8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Color(0xFFDE5F8B),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Premium feature',
                    style: TextStyle(
                      color: Color(0xFFDE5F8B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                switch (feature) {
                  'Plant health screening' ||
                  'Plant Health Checker' => 'Help your plants thrive.',
                  'Plant Care' => 'Unlock detailed plant care.',
                  'Advanced plant biology' => 'Explore advanced plant biology.',
                  'Detailed nutrient information' =>
                    'Understand plant nutrients in more detail.',
                  'Growth and care tracker' =>
                    'Track growth and plant-care activities.',
                  'AI plant assistant' => 'Get personalized plant-care help.',
                  'Advanced plant information' =>
                    'Unlock more plant science and care details.',
                  _ => 'Every stage matters.',
                },
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                switch (feature) {
                  'Plant health screening' || 'Plant Health Checker' =>
                    'Understand plant health and discover possible problems.',
                  'Plant Care' => 'Get plant-specific watering, sunlight, soil, fertilizer, and maintenance guidance.',
                  'Advanced plant biology' => 'View advanced species biology, growth, habitat, and life-cycle information.',
                  'Detailed nutrient information' => 'Explore detailed nutrient roles, deficiency information, and fertilizer guidance.',
                  'Growth and care tracker' => 'Record growth observations, care activities, and plant progress.',
                  'AI plant assistant' =>
                    'Ask LUMIN AI for personalized plant-care assistance.',
                  'Advanced plant information' => 'View expanded species information, growing conditions, and care details.',
                  _ => 'Build better plant care habits and keep an eye on every stage.',
                },
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Premium unlocks all advanced monitoring tools.',
                style: TextStyle(
                  color: AppColors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, '/premium'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    feature == 'Plant health screening'
                        ? 'Explore Subscription'
                        : 'Explore Subscription',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String? safePlantImageUrl(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri.toString();
}

class PlantPhoto extends StatelessWidget {
  const PlantPhoto({
    super.key,
    required this.asset,
    this.imageUrl,
    this.height = 140,
  });

  final String asset;
  final String? imageUrl;
  final double height;

  @override
  Widget build(BuildContext context) {
    final safeImageUrl = safePlantImageUrl(imageUrl);
    final placeholder = Container(
      width: double.infinity,
      height: height,
      color: AppColors.background,
      child: const Icon(Icons.eco_outlined, color: AppColors.green, size: 40),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: safeImageUrl != null
          ? Image.network(
              safeImageUrl,
              width: double.infinity,
              height: height,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: double.infinity,
                  height: height,
                  color: AppColors.background,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: AppColors.green,
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
              errorBuilder: (_, _, _) => asset.trim().isEmpty
                  ? placeholder
                  : Image.asset(
                      asset,
                      width: double.infinity,
                      height: height,
                      fit: BoxFit.cover,
                    ),
            )
          : asset.trim().isEmpty
          ? placeholder
          : Image.asset(
              asset,
              width: double.infinity,
              height: height,
              fit: BoxFit.cover,
            ),
    );
  }
}
