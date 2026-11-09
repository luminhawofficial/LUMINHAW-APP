import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';

class LuminAssistantOverlay extends StatelessWidget {
  const LuminAssistantOverlay({
    required this.child,
    this.aboveBottomBar = false,
    super.key,
  });

  final Widget child;
  final bool aboveBottomBar;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          right: 18,
          bottom: bottomInset + (aboveBottomBar ? 82 : 16),
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 5,
            shadowColor: AppColors.dark.withValues(alpha: 0.24),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pushNamed('/assistant'),
              child: Tooltip(
                message: 'Open Lumin AI',
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/ai_lumin_logo.png',
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
