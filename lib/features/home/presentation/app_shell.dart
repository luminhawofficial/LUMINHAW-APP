import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:luminhaw/features/ai_assistant/lumin_assistant_overlay.dart';
import 'package:luminhaw/features/garden/garden_page.dart';
import 'package:luminhaw/features/library/library_page.dart';
import 'package:luminhaw/features/profile/profile_page.dart';
import 'package:luminhaw/features/scanner/scanner_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialTab;

  late final List<Widget> _tabs = [
    const HomeTab(),
    const LibraryPage(),
    const ScannerPage(),
    const GardenPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return LuminAssistantOverlay(
      aboveBottomBar: true,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: IndexedStack(index: _index, children: _tabs),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            height: 74,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0x1A0B5E48))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    active: _index == 0,
                    onTap: () => setState(() => _index = 0),
                  ),
                ),
                Expanded(
                  child: _TabButton(
                    icon: Icons.menu_book_outlined,
                    label: 'Library',
                    active: _index == 1,
                    onTap: () => setState(() => _index = 1),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _index = 2),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(
                              color: AppColors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_outlined,
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Scan',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 9,
                                height: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _TabButton(
                    icon: Icons.yard_outlined,
                    label: 'Garden',
                    active: _index == 3,
                    onTap: () => setState(() => _index = 3),
                  ),
                ),
                Expanded(
                  child: _TabButton(
                    icon: Icons.person_outline,
                    label: 'Profile',
                    active: _index == 4,
                    onTap: () => setState(() => _index = 4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.green : AppColors.muted;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final narrowScreen = MediaQuery.sizeOf(context).width < 360;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning, Plant lover!'
        : hour < 17
        ? 'Good afternoon, Plant lover!'
        : 'Good evening, Plant lover!';

    return Column(
      children: [
        const AppHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            children: [
              Text(
                greeting,
                style: const TextStyle(
                  color: AppColors.green,
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Let's help your plants thrive.",
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              AppCard(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Identify a Plant',
                                style: TextStyle(
                                  color: AppColors.green,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Discover any plant in seconds.',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () =>
                                    Navigator.pushNamed(context, '/scan'),
                                icon: const Icon(Icons.camera_alt, size: 16),
                                label: Text(
                                  narrowScreen ? 'Scan' : 'Scan a Plant',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.green,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: narrowScreen ? 6 : 12,
                                    vertical: 9,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: narrowScreen ? 72 : 124,
                        height: 150,
                        child: Image.asset(
                          'assets/images/plants/plant_1.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const SizedBox(height: 22),
              _SectionTitle(
                title: 'Your Garden',
                action: 'View all',
                onTap: () => Navigator.pushNamed(context, '/garden'),
              ),
              const SizedBox(height: 10),
              const _HomeGardenPreview(),
              const SizedBox(height: 18),
              const _SectionTitle(title: 'Plant Care Tips'),
              const SizedBox(height: 10),
              AppCard(
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/images/plants/plant_2.png',
                        width: 78,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Check the soil before watering',
                            style: TextStyle(
                              color: AppColors.green,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'A quick soil check can help prevent overwatering.',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onTap});

  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.green,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            child: Text(action!, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}

class _PlantPreview extends StatelessWidget {
  const _PlantPreview({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, Map<String, Object?>>>(
      valueListenable: LocalPlantDataStore.instance.gardenPlantDetails,
      builder: (context, details, _) {
        final plant = PlantRecord.fromStoredDetails(name, details[name]);
        return SizedBox(
          width: 132,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: AppCard(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 78,
                    width: 116,
                    child: PlantPhoto(
                      asset: plant.image,
                      imageUrl: plant.imageUrl,
                      height: 78,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeGardenPreview extends StatefulWidget {
  const _HomeGardenPreview();

  @override
  State<_HomeGardenPreview> createState() => _HomeGardenPreviewState();
}

class _HomeGardenPreviewState extends State<_HomeGardenPreview> {
  final _store = LocalPlantDataStore.instance;
  late Future<void> _loading = _store.load();

  void _retryLoad() {
    setState(() {
      _store.retryLoad();
      _loading = _store.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not load your garden: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.dark, fontSize: 12),
                ),
                TextButton(
                  onPressed: _retryLoad,
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppCard(
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(Icons.yard_outlined, color: AppColors.green),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Loading your garden…',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              ],
            ),
          );
        }

        return ValueListenableBuilder<Object?>(
          valueListenable: _store.loadError,
          builder: (context, error, _) {
            if (error != null) {
              return AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Could not load your garden: $error',
                      style: const TextStyle(
                        color: AppColors.dark,
                        fontSize: 12,
                      ),
                    ),
                    TextButton(
                      onPressed: _retryLoad,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              );
            }
            return ValueListenableBuilder<List<String>>(
              valueListenable: _store.gardenPlantNames,
              builder: (context, names, _) {
                if (names.isEmpty) {
                  return AppCard(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final message = Row(
                          children: [
                            const Icon(
                              Icons.yard_outlined,
                              color: AppColors.green,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Your garden is ready to grow.',
                                style: TextStyle(
                                  color: AppColors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        );
                        final addButton = TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/library'),
                          child: const Text('Add a plant'),
                        );
                        if (constraints.maxWidth < 320) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              message,
                              Align(
                                alignment: Alignment.centerRight,
                                child: addButton,
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            const Icon(
                              Icons.yard_outlined,
                              color: AppColors.green,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Your garden is ready to grow.',
                                style: TextStyle(
                                  color: AppColors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            addButton,
                          ],
                        );
                      },
                    ),
                  );
                }

                return SizedBox(
                  height: 145,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final name in names) _PlantPreview(name: name),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
