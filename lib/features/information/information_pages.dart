import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _features = [
    'Basic plant identification, basic library information, recent scans, saved plants, and 10 LUMIN AI messages per day',
    'Premium advanced biology, nutrient information, AI health screening, detailed care guides, growth tracking, and higher LUMIN AI limits',
    'Manage garden records on this device or sync them to a verified account',
    'Identify a plant after confirming photo processing',
    'Review cloud scan history when connected',
  ];

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'About',
      subtitle: 'A little more about LUMINHAW.',
      back: true,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LUMINHAW helps plant lovers learn about plants and build thoughtful care routines. Basic access includes plant identification, basic plant information and care, the plant library, local names, recent scans, saved plants, and 10 LUMIN AI assistant messages per day. Premium adds advanced biology and nutrients, AI health screening, detailed care guides, growth tracking, and higher LUMIN AI usage limits. Account access uses Supabase Authentication. Garden records stay on this device when signed out and sync to an owner-scoped account when signed in with verified email. Saved Library plant details remain device-only and are separate from My Garden. Existing device-only records are not automatically uploaded. Plant identification can use Plant.ID with PlantNet fallback, and plant search can use Perenual with GBIF fallback when the Edge Functions and provider configuration are available. LUMIN AI uses Gemini and requires a verified email; the Basic daily limit is enforced by the server. Catalog entries are shown only when returned by an online provider.',
              style: TextStyle(color: AppColors.muted, height: 1.55),
            ),
            const SizedBox(height: 20),
            const Text(
              'Key features',
              style: TextStyle(
                color: AppColors.green,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            for (final feature in _features)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.eco_outlined,
                      size: 18,
                      color: AppColors.green,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        feature,
                        style: const TextStyle(
                          color: AppColors.muted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const SetupNotice(
              message: 'Plant advice and health screening are educational only. No diagnosis or identification is guaranteed.',
            ),
          ],
        ),
      ),
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'Privacy & usage.',
      subtitle: 'How the current app handles your information.',
      back: true,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _DisclosureSection(
              title: 'Privacy',
              body: 'LUMINHAW uses Supabase Authentication for account creation, sign-in, email verification, and password recovery. The email and name you submit are sent to the configured Supabase project. Your active session is maintained by the Supabase client. While signed out, garden plants, care activities, and growth observations are stored on this device. With a verified signed-in account, these records sync to owner-scoped Supabase tables. Library plant details saved in Settings are stored only on this device and are separate from My Garden. Existing device-only records are not automatically uploaded or attributed to an account. Onboarding preferences remain on this device.',
            ),
            _DisclosureSection(
              title: 'Photos and external services',
              body: 'A photo selected for plant identification is sent to the configured Supabase Edge Function and Plant.ID, with PlantNet fallback, for analysis only after you confirm in the scanner. The identification image is sent for processing and is not saved to the app storage bucket; scan status and results are saved in your Supabase scan history. Plant-health photos are uploaded to the private per-user photo bucket for assessment, and their assessment records are saved to your account. Plant health screening requires verified Premium entitlement. Optional payment receipts are stored in private Supabase storage and may be linked to the designated payment-review email using an expiring signed URL. Payment references, dates, and statuses are stored with payment requests. A photo that is not submitted stays on this device. Verified accounts can send up to 10 LUMIN AI assistant messages per UTC day on Basic; when you send a message, the message and up to six recent conversation messages are sent through the Supabase Edge Function to Gemini. Premium accounts use a separate higher rate limit. Catalog search terms may be sent to Perenual or the public GBIF API. Review provider privacy and retention terms before release.',
            ),
            _DisclosureSection(
              title: 'Notifications',
              body: 'Care reminders are opt-in local notifications scheduled on this device from plants saved in My Garden. The reminder preference and schedules are stored locally, and notification text may appear on the device lock screen. System announcements are app-wide public messages loaded from the configured Supabase project; do not include private account data in announcements.',
            ),
            _DisclosureSection(
              title: 'Account data',
              body: 'A signed-in account may have its email, display name, garden plants, care activities, growth observations, scan history, health assessments, and payment request records stored in Supabase. The included database migrations define owner-scoped row-level security and private photo storage; those protections take effect only after deployment. Account deletion is available in Profile after the deletion Edge Function and security migration are deployed; deletion removes the account, associated cloud records, and private photos including payment evidence. Device-only data is not automatically uploaded.',
            ),
            _DisclosureSection(
              title: 'Subscriptions',
              body: 'Manual GCash payments require an approved merchant receiving method, confirmed pricing, receipt validation, and email review. Payments are disabled until configured. Submitting a transaction reference or receipt does not activate Premium; only an explicit approval after checking the actual transaction can activate access. Google Play Billing and automatic GCash processing are not configured.',
            ),
            _DisclosureSection(
              title: 'Usage terms',
              body: 'Plant information and future AI-generated identification or health guidance are educational estimates, not professional or guaranteed advice. Check important plant-care decisions against reliable botanical sources.',
            ),
            _DisclosureSection(
              title: 'Policy publication',
              body: 'This in-app disclosure is not a substitute for a reviewed, publicly hosted privacy policy. Before Google Play release, publish the policy URL, add the publisher contact and applicable data-retention details, configure Supabase email delivery and redirects, deploy the migrations and Edge Functions, and complete the Play Console data-safety and account-deletion declarations. This page is not legal advice.',
            ),
          ],
        ),
      ),
    );
  }
}

class _DisclosureSection extends StatelessWidget {
  const _DisclosureSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.green,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            body,
            style: const TextStyle(color: AppColors.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
