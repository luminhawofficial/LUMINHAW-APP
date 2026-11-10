import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';

void main() {
  final entitlements = PlanEntitlementStore.instance;

  tearDown(() {
    entitlements.tier.value = PlanTier.free;
  });

  test('free tier does not receive Premium access in debug builds', () {
    entitlements.tier.value = PlanTier.free;

    expect(entitlements.hasPremiumAccess, isFalse);
  });

  test('verified Premium tier receives Premium access', () {
    entitlements.tier.value = PlanTier.premium;

    expect(entitlements.hasPremiumAccess, isTrue);
  });
}
