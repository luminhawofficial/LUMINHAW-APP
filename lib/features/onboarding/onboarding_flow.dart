import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:luminhaw/features/authentication/auth_screens.dart';
import 'package:luminhaw/features/home/presentation/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppEntry extends StatelessWidget {
  const AppEntry({super.key});

  Future<bool> _hasCompletedIntro() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool('onboarding_complete') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasCompletedIntro(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not load your saved onboarding preference.',
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pushReplacementNamed(context, '/'),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.green),
            ),
          );
        }
        if (SupabaseAuthService.currentUser != null) {
          return const AppShell();
        }
        return snapshot.data! ? const LoginPage() : const IntroPage();
      },
    );
  }
}

Future<void> completeOnboarding(BuildContext context) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool('onboarding_complete', true);
  if (context.mounted) {
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (_) => false);
  }
}

class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              Image.asset('assets/icons/logo.png', width: 108, height: 108),
              const SizedBox(height: 14),
              const Text(
                'LUMINHAW',
                style: TextStyle(
                  color: AppColors.green,
                  fontFamily: 'Cinzel',
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  fontVariations: [FontVariation.weight(700)],
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Know your Plant, Nurture their Future',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward,
                onPressed: () => Navigator.pushNamed(context, '/onboarding'),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = [
    _OnboardingSlide(
      title: 'Discover the green around you.',
      description: 'Scan a plant to explore its name, scientific details, family, and care.',
      image: 'assets/images/plants/plant_1.png',
      step: '1 OF 3',
    ),
    _OnboardingSlide(
      title: 'Keep your garden close.',
      description:
          'Save plants, revisit your scans, and build a collection you love.',
      image: 'assets/images/plants/plant_2.png',
      step: '2 OF 3',
    ),
    _OnboardingSlide(
      title: 'Go deeper with Premium.',
      description: 'Explore advanced plant biology, care guides, growth tracking, and AI assistance.',
      image: 'assets/images/plants/plant_3.png',
      step: '3 OF 3',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length - 1;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              showPlan: false,
              showNotifications: false,
              trailing: TextButton(
                onPressed: () => completeOnboarding(context),
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) =>
                    _OnboardingSlideView(slide: _slides[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: index == _index ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: index == _index
                              ? AppColors.green
                              : AppColors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  PrimaryButton(
                    label: isLast ? 'Get started' : 'Next',
                    icon: Icons.arrow_forward,
                    onPressed: () {
                      if (isLast) {
                        completeOnboarding(context);
                      } else {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.title,
    required this.description,
    required this.image,
    required this.step,
  });

  final String title;
  final String description;
  final String image;
  final String step;
}

class _OnboardingSlideView extends StatelessWidget {
  const _OnboardingSlideView({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 6, 28, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 230,
            height: 230,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFFDFF0D9),
              shape: BoxShape.circle,
            ),
            child: Image.asset(slide.image, fit: BoxFit.contain),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDDEBDD),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              slide.step,
              style: const TextStyle(
                color: AppColors.green,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.dark,
              fontFamily: 'PlayfairDisplay',
              fontSize: 23,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            slide.description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/icons/logo.png', width: 56, height: 56),
                    const SizedBox(height: 10),
                    const Text(
                      'YOUR PLANT JOURNEY STARTS HERE',
                      style: TextStyle(
                        color: AppColors.green,
                        fontSize: 9,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Know your\nplants.\nNurture their\nfuture.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.green,
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 30,
                        height: 1.08,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 230,
                      child: Image.asset(
                        'assets/images/plants/plant_4.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'A little knowledge. A little care.\nA greener everyday.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Log in',
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.pushNamed(context, '/signup'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: AppColors.green,
                        side: const BorderSide(color: AppColors.green),
                      ),
                      child: const Text('Create an account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
