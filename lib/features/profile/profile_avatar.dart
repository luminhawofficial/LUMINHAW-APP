import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/profile_photo_service.dart';

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.radius,
    this.refreshToken = 0,
  });

  final double radius;
  final int refreshToken;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  late Future<String?> _avatarUrl;

  @override
  void initState() {
    super.initState();
    _avatarUrl = ProfilePhotoService.avatarUrl();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _avatarUrl = ProfilePhotoService.avatarUrl();
    }
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;
    return FutureBuilder<String?>(
      future: _avatarUrl,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) return _placeholder();

        return ClipOval(
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _placeholder(),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder() => CircleAvatar(
    radius: widget.radius,
    backgroundColor: const Color(0xFFD9EADB),
    child: Icon(
      Icons.person,
      color: AppColors.green,
      size: widget.radius * 0.97,
    ),
  );
}
