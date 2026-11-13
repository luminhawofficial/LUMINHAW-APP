import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

GrowthEntry? initialGrowthPhotoForPlant(
  String plantName,
  Iterable<GrowthEntry> entries,
) {
  final normalizedName = plantName.trim().toLowerCase();
  GrowthEntry? initialPhoto;
  for (final entry in entries) {
    final hasPhoto =
        (entry.photoDataBase64?.isNotEmpty ?? false) ||
        (entry.photoPath?.isNotEmpty ?? false);
    if (!hasPhoto || entry.plantName.trim().toLowerCase() != normalizedName) {
      continue;
    }
    if (initialPhoto == null || entry.date.isBefore(initialPhoto.date)) {
      initialPhoto = entry;
    }
  }
  return initialPhoto;
}

class PlantCoverPhoto extends StatelessWidget {
  const PlantCoverPhoto({
    super.key,
    required this.plant,
    this.width,
    this.height = 140,
  });

  final PlantRecord plant;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fallback = PlantPhoto(
      asset: plant.image,
      imageUrl: plant.imageUrl,
      height: height,
    );
    return SizedBox(
      width: width,
      height: height,
      child: ValueListenableBuilder<List<GrowthEntry>>(
        valueListenable: LocalPlantDataStore.instance.growthEntries,
        builder: (context, entries, _) {
          final initialPhoto = initialGrowthPhotoForPlant(
            plant.commonName,
            entries,
          );
          if (initialPhoto == null) return fallback;
          return GrowthEntryPhoto(
            entry: initialPhoto,
            width: width ?? double.infinity,
            height: height,
            borderRadius: 16,
            fallback: fallback,
          );
        },
      ),
    );
  }
}

class GrowthEntryPhoto extends StatefulWidget {
  const GrowthEntryPhoto({
    super.key,
    required this.entry,
    this.width = 120,
    this.height = 96,
    this.borderRadius = 10,
    this.fallback,
  });

  final GrowthEntry entry;
  final double width;
  final double height;
  final double borderRadius;
  final Widget? fallback;

  @override
  State<GrowthEntryPhoto> createState() => _GrowthEntryPhotoState();
}

class _GrowthEntryPhotoState extends State<GrowthEntryPhoto> {
  late Future<String?> _photoUrl = _loadPhotoUrl();

  @override
  void didUpdateWidget(covariant GrowthEntryPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.photoPath != widget.entry.photoPath) {
      _photoUrl = _loadPhotoUrl();
    }
  }

  Future<String?> _loadPhotoUrl() async {
    final path = widget.entry.photoPath;
    final user = SupabaseAuthService.currentUser;
    if (!SupabaseBackend.isInitialized ||
        path == null ||
        user == null ||
        !path.startsWith('${user.id}/growth/')) {
      return null;
    }
    return SupabaseBackend.client.storage
        .from('plant-photos')
        .createSignedUrl(path, 60 * 60);
  }

  Widget _fallback() => widget.fallback ?? const SizedBox.shrink();

  Widget _image(String url) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.borderRadius),
    child: Image.network(
      url,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _fallback(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final photoData = widget.entry.photoDataBase64;
    if (photoData != null) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Image.memory(
            base64Decode(photoData),
            height: widget.height,
            width: widget.width,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _fallback(),
          ),
        );
      } on FormatException {
        return _fallback();
      }
    }

    return FutureBuilder<String?>(
      future: _photoUrl,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty || snapshot.hasError) {
          return _fallback();
        }
        return _image(url);
      },
    );
  }
}
