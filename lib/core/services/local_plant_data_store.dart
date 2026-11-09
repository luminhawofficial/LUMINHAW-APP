import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_backend.dart';

class GrowthEntry {
  const GrowthEntry({
    required this.id,
    required this.plantName,
    required this.activity,
    required this.date,
    required this.notes,
    this.heightCm,
    this.leafCount,
    this.photoPath,
    this.photoDataBase64,
  });

  final String id;
  final String plantName;
  final String activity;
  final DateTime date;
  final String notes;
  final double? heightCm;
  final int? leafCount;
  final String? photoPath;
  final String? photoDataBase64;

  Map<String, Object?> toJson() => {
    'id': id,
    'plantName': plantName,
    'activity': activity,
    'date': date.toIso8601String(),
    'notes': notes,
    'heightCm': heightCm,
    'leafCount': leafCount,
    'photoPath': photoPath,
    'photoDataBase64': photoDataBase64,
  };

  factory GrowthEntry.fromJson(Map<String, dynamic> json) => GrowthEntry(
    id: json['id'] as String,
    plantName: json['plantName'] as String,
    activity: json['activity'] as String,
    date: DateTime.parse(json['date'] as String),
    notes: json['notes'] as String? ?? '',
    heightCm: (json['heightCm'] as num?)?.toDouble(),
    leafCount: (json['leafCount'] as num?)?.toInt(),
    photoPath: json['photoPath'] as String?,
    photoDataBase64: json['photoDataBase64'] as String?,
  );

  GrowthEntry copyWith({String? photoPath, String? photoDataBase64}) =>
      GrowthEntry(
        id: id,
        plantName: plantName,
        activity: activity,
        date: date,
        notes: notes,
        heightCm: heightCm,
        leafCount: leafCount,
        photoPath: photoPath ?? this.photoPath,
        photoDataBase64: photoDataBase64 ?? this.photoDataBase64,
      );
}

class CompletedCareTask {
  const CompletedCareTask({
    required this.id,
    required this.plantName,
    required this.title,
    required this.recommendation,
    required this.dueAt,
    required this.completedAt,
    required this.notes,
  });

  final String id;
  final String plantName;
  final String title;
  final String recommendation;
  final DateTime dueAt;
  final DateTime completedAt;
  final String notes;

  Map<String, Object?> toJson() => {
    'id': id,
    'plantName': plantName,
    'title': title,
    'recommendation': recommendation,
    'dueAt': dueAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'notes': notes,
  };

  factory CompletedCareTask.fromJson(Map<String, dynamic> json) =>
      CompletedCareTask(
        id: json['id'] as String,
        plantName: json['plantName'] as String,
        title: json['title'] as String,
        recommendation: json['recommendation'] as String,
        dueAt: DateTime.parse(json['dueAt'] as String),
        completedAt: DateTime.parse(json['completedAt'] as String),
        notes: json['notes'] as String? ?? '',
      );
}

class LocalPlantDataStore {
  LocalPlantDataStore();

  static final instance = LocalPlantDataStore();
  static const _gardenKey = 'local_garden_plant_names';
  static const _gardenDetailsKey = 'local_garden_plant_details';
  static const _entriesKey = 'local_growth_entries';
  static const _careTasksKey = 'local_completed_care_tasks';
  static const maximumObservationPhotoBytes = 2 * 1024 * 1024;

  final ValueNotifier<List<String>> gardenPlantNames = ValueNotifier(const []);
  final ValueNotifier<Map<String, Map<String, Object?>>> gardenPlantDetails =
      ValueNotifier(const {});
  final ValueNotifier<List<GrowthEntry>> growthEntries = ValueNotifier(
    const [],
  );
  final ValueNotifier<List<CompletedCareTask>> completedCareTasks =
      ValueNotifier(const []);
  final ValueNotifier<Object?> loadError = ValueNotifier(null);

  Future<void>? _loadFuture;
  String? _activeScope;
  StreamSubscription<AuthState>? _authSubscription;

  bool get isCloudSynced => _activeScope != null && _activeScope != 'device';

  Future<void> load() {
    _listenForAuthChanges();
    final scope = _currentScope;
    if (_activeScope != scope) {
      _activateScope(scope);
    } else {
      _loadFuture ??= _loadForScope(scope);
    }
    return _loadFuture!;
  }

  void retryLoad() {
    _loadFuture = null;
    loadError.value = null;
  }

  String get _currentScope {
    final user = SupabaseAuthService.currentUser;
    return user == null ? 'device' : 'account:${user.id}';
  }

  void _listenForAuthChanges() {
    if (_authSubscription != null || !SupabaseBackend.isInitialized) return;
    _authSubscription = SupabaseBackend.client.auth.onAuthStateChange.listen((
      _,
    ) {
      final scope = _currentScope;
      if (scope == _activeScope) return;
      _activateScope(scope);
      unawaited(_loadFuture!.catchError((Object _) {}));
    });
  }

  void _activateScope(String scope) {
    _activeScope = scope;
    _loadFuture = null;
    loadError.value = null;
    gardenPlantNames.value = const [];
    gardenPlantDetails.value = const {};
    growthEntries.value = const [];
    completedCareTasks.value = const [];
    _loadFuture = _loadForScope(scope);
  }

  Future<void> _loadForScope(String scope) async {
    loadError.value = null;
    try {
      if (scope == 'device') {
        await _loadFromPreferences();
      } else {
        _requireVerifiedUser();
        await _loadFromCloud(scope);
      }
    } catch (error) {
      loadError.value = error;
      rethrow;
    }
  }

  User _requireVerifiedUser() {
    final user = SupabaseAuthService.currentUser;
    if (user == null) {
      throw StateError('Sign in to load your cloud garden.');
    }
    if (user.emailConfirmedAt == null) {
      throw StateError('Verify your email to sync garden and growth data.');
    }
    return user;
  }

  Future<void> _loadFromPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    final names = preferences.getStringList(_gardenKey) ?? const [];
    final encodedDetails = preferences.getString(_gardenDetailsKey);
    final details = <String, Map<String, Object?>>{};
    if (encodedDetails != null) {
      final decoded = jsonDecode(encodedDetails);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.key is String && entry.value is Map) {
            details[entry.key as String] = Map<String, Object?>.from(
              entry.value as Map,
            );
          }
        }
      }
    }
    final encodedEntries = preferences.getString(_entriesKey);
    final entries = encodedEntries == null
        ? <GrowthEntry>[]
        : (jsonDecode(encodedEntries) as List<dynamic>)
              .map(
                (entry) => GrowthEntry.fromJson(entry as Map<String, dynamic>),
              )
              .toList();
    await _loadCareTasks('device');
    entries.sort((a, b) => b.date.compareTo(a.date));
    gardenPlantNames.value = List.unmodifiable(names);
    gardenPlantDetails.value = Map.unmodifiable(details);
    growthEntries.value = List.unmodifiable(entries);
  }

  Future<void> _loadFromCloud(String scope) async {
    final client = SupabaseBackend.client;
    final plants = await client
        .from('plants')
        .select('id, common_name, catalog_details')
        .order('created_at');
    final namesById = <String, String>{};
    final detailsByName = <String, Map<String, Object?>>{};
    for (final row in plants) {
      final name = row['common_name'] as String;
      namesById[row['id'] as String] = name;
      final details = row['catalog_details'];
      if (details is Map && details.isNotEmpty) {
        detailsByName[name] = Map<String, Object?>.from(details);
      }
    }

    final entries = <GrowthEntry>[];
    final growthRows = await client
        .from('growth_entries')
        .select(
          'id, plant_id, observed_on, height_cm, leaf_count, notes, image_path',
        )
        .order('observed_on', ascending: false);
    for (final row in growthRows) {
      final plantName = namesById[row['plant_id'] as String];
      if (plantName == null) continue;
      entries.add(
        GrowthEntry(
          id: row['id'] as String,
          plantName: plantName,
          activity: 'Observation',
          date: DateTime.parse(row['observed_on'] as String),
          notes: row['notes'] as String? ?? '',
          heightCm: (row['height_cm'] as num?)?.toDouble(),
          leafCount: (row['leaf_count'] as num?)?.toInt(),
          photoPath: row['image_path'] as String?,
        ),
      );
    }

    final careRows = await client
        .from('care_activities')
        .select('id, plant_id, activity, notes, occurred_at')
        .order('occurred_at', ascending: false);
    for (final row in careRows) {
      final plantName = namesById[row['plant_id'] as String];
      if (plantName == null) continue;
      entries.add(
        GrowthEntry(
          id: row['id'] as String,
          plantName: plantName,
          activity: _displayActivity(row['activity'] as String),
          date: DateTime.parse(row['occurred_at'] as String).toLocal(),
          notes: row['notes'] as String? ?? '',
        ),
      );
    }

    await _loadCareTasks(scope);
    entries.sort((a, b) => b.date.compareTo(a.date));
    gardenPlantNames.value = List.unmodifiable(
      plants.map((row) => row['common_name'] as String),
    );
    gardenPlantDetails.value = Map.unmodifiable(detailsByName);
    growthEntries.value = List.unmodifiable(entries);
    loadError.value = null;
  }

  Future<bool> addPlant(
    String commonName, {
    Map<String, Object?>? details,
  }) async {
    await load();
    final name = commonName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(commonName, 'commonName', 'Must not be empty.');
    }
    if (gardenPlantNames.value.contains(name)) {
      if (details != null) await _savePlantDetails(name, details);
      return false;
    }

    if (_activeScope != 'device') {
      final user = _requireVerifiedUser();
      final client = SupabaseBackend.client;
      final existing = await client
          .from('plants')
          .select('id')
          .eq('common_name', name)
          .maybeSingle();
      if (existing != null) {
        if (details != null) {
          await client
              .from('plants')
              .update({'catalog_details': details})
              .eq('id', existing['id'] as String);
          gardenPlantDetails.value = Map.unmodifiable({
            ...gardenPlantDetails.value,
            name: details,
          });
        }
        return false;
      }
      final row = <String, Object?>{'owner_id': user.id, 'common_name': name};
      if (details != null) row['catalog_details'] = details;
      await client.from('plants').insert(row);
      gardenPlantNames.value = List.unmodifiable([
        ...gardenPlantNames.value,
        name,
      ]);
      if (details != null) {
        gardenPlantDetails.value = Map.unmodifiable({
          ...gardenPlantDetails.value,
          name: details,
        });
      }
      return true;
    }

    final updatedNames = [...gardenPlantNames.value, name];
    final preferences = await SharedPreferences.getInstance();
    final updatedDetails = {...gardenPlantDetails.value};
    if (details != null) updatedDetails[name] = details;
    if (details != null) {
      final detailsSaved = await preferences.setString(
        _gardenDetailsKey,
        jsonEncode(updatedDetails),
      );
      if (!detailsSaved) {
        throw StateError('Plant details could not be saved to this device.');
      }
    }
    final saved = await preferences.setStringList(_gardenKey, updatedNames);
    if (!saved) {
      throw StateError('The plant could not be saved to this device.');
    }
    gardenPlantNames.value = List.unmodifiable(updatedNames);
    gardenPlantDetails.value = Map.unmodifiable(updatedDetails);
    return true;
  }

  Future<void> _savePlantDetails(
    String name,
    Map<String, Object?> details,
  ) async {
    final updatedDetails = {...gardenPlantDetails.value, name: details};
    if (_activeScope != 'device') {
      await SupabaseBackend.client
          .from('plants')
          .update({'catalog_details': details})
          .eq('owner_id', _requireVerifiedUser().id)
          .eq('common_name', name);
    } else {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setString(
        _gardenDetailsKey,
        jsonEncode(updatedDetails),
      );
      if (!saved) {
        throw StateError('Plant details could not be saved to this device.');
      }
    }
    gardenPlantDetails.value = Map.unmodifiable(updatedDetails);
  }

  Future<bool> removePlant(String commonName) async {
    await load();
    final name = commonName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(commonName, 'commonName', 'Must not be empty.');
    }
    if (!gardenPlantNames.value.contains(name)) return false;

    if (_activeScope != 'device') {
      await SupabaseBackend.client
          .from('plants')
          .delete()
          .eq('common_name', name);
      final updatedDetails = {...gardenPlantDetails.value}..remove(name);
      gardenPlantNames.value = List.unmodifiable(
        gardenPlantNames.value.where((plantName) => plantName != name),
      );
      gardenPlantDetails.value = Map.unmodifiable(updatedDetails);
      growthEntries.value = List.unmodifiable(
        growthEntries.value.where((entry) => entry.plantName != name),
      );
      await _removeCareTasksForPlant(name);
      return true;
    }

    final updatedNames = gardenPlantNames.value
        .where((plantName) => plantName != name)
        .toList();
    final updatedDetails = {...gardenPlantDetails.value}..remove(name);
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setStringList(_gardenKey, updatedNames);
    if (!saved) {
      throw StateError('The plant could not be removed from this device.');
    }
    final detailsSaved = await preferences.setString(
      _gardenDetailsKey,
      jsonEncode(updatedDetails),
    );
    if (!detailsSaved) {
      throw StateError('Plant details could not be removed from this device.');
    }
    gardenPlantNames.value = List.unmodifiable(updatedNames);
    gardenPlantDetails.value = Map.unmodifiable(updatedDetails);
    await _removeCareTasksForPlant(name);
    return true;
  }

  String _careTasksStorageKey(String scope) {
    final owner = scope == 'device'
        ? 'device'
        : scope.substring('account:'.length);
    return '${_careTasksKey}_$owner';
  }

  Future<void> _loadCareTasks(String scope) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_careTasksStorageKey(scope));
    if (encoded == null) {
      if (scope == _activeScope) completedCareTasks.value = const [];
      return;
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Saved care task history is invalid.');
    }
    final tasks = decoded
        .map(
          (task) => CompletedCareTask.fromJson(
            Map<String, dynamic>.from(task as Map),
          ),
        )
        .toList();
    tasks.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    if (scope == _activeScope) {
      completedCareTasks.value = List.unmodifiable(tasks);
    }
  }

  Future<void> saveCompletedCareTask(CompletedCareTask task) async {
    await load();
    if (task.id.trim().isEmpty ||
        task.plantName.trim().isEmpty ||
        task.title.trim().isEmpty) {
      throw ArgumentError(
        'A completed care task needs an ID, plant, and title.',
      );
    }
    if (!gardenPlantNames.value.contains(task.plantName.trim())) {
      throw StateError('Add this plant to My Garden before tracking its care.');
    }
    if (completedCareTasks.value.any((saved) => saved.id == task.id)) {
      throw StateError('This care task has already been completed.');
    }
    final updated = [task, ...completedCareTasks.value]
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _careTasksStorageKey(_activeScope!),
      jsonEncode(updated.map((item) => item.toJson()).toList()),
    );
    if (!saved) {
      throw StateError(
        'Care task completion could not be saved on this device.',
      );
    }
    completedCareTasks.value = List.unmodifiable(updated);
  }

  Future<void> _removeCareTasksForPlant(String plantName) async {
    final updated = completedCareTasks.value
        .where((task) => task.plantName != plantName)
        .toList();
    if (updated.length == completedCareTasks.value.length) return;
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _careTasksStorageKey(_activeScope!),
      jsonEncode(updated.map((task) => task.toJson()).toList()),
    );
    if (!saved) {
      throw StateError(
        'Care task history could not be removed from this device.',
      );
    }
    completedCareTasks.value = List.unmodifiable(updated);
  }

  Future<void> recordCareActivity({
    required String plantName,
    required String activity,
  }) async {
    final timestamp = DateTime.now();
    await saveGrowthEntry(
      GrowthEntry(
        id: 'care-${timestamp.microsecondsSinceEpoch}',
        plantName: plantName,
        activity: activity,
        date: timestamp,
        notes: '',
      ),
    );
  }

  Future<void> saveGrowthEntry(
    GrowthEntry entry, {
    Uint8List? photoBytes,
  }) async {
    await load();
    if (entry.id.trim().isEmpty || entry.plantName.trim().isEmpty) {
      throw ArgumentError('A journal entry needs an ID and plant name.');
    }
    if (!gardenPlantNames.value.contains(entry.plantName.trim())) {
      throw StateError(
        'Add this plant to My Garden before saving growth or care records.',
      );
    }
    if (entry.heightCm != null &&
        (!entry.heightCm!.isFinite || entry.heightCm! < 0)) {
      throw ArgumentError.value(entry.heightCm, 'heightCm');
    }
    if (entry.leafCount != null && entry.leafCount! < 0) {
      throw ArgumentError.value(entry.leafCount, 'leafCount');
    }
    if (photoBytes != null &&
        (photoBytes.isEmpty ||
            photoBytes.length > maximumObservationPhotoBytes)) {
      throw ArgumentError.value(
        photoBytes.length,
        'photoBytes',
        'Observation photos must be at most 2 MB.',
      );
    }
    final contentType = photoBytes == null
        ? null
        : _imageContentType(photoBytes);
    if (photoBytes != null && contentType == null) {
      throw const FormatException(
        'Choose a JPEG, PNG, or WebP observation photo.',
      );
    }
    if (_activeScope != 'device') {
      final user = _requireVerifiedUser();
      if (photoBytes == null) {
        await _saveCloudEntry(entry, user);
        return;
      }

      final extension = switch (contentType) {
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => throw const FormatException(
          'Choose a JPEG, PNG, or WebP observation photo.',
        ),
      };
      final photoPath = '${user.id}/growth/${entry.id}.$extension';
      await SupabaseBackend.client.storage
          .from('plant-photos')
          .uploadBinary(
            photoPath,
            photoBytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
      try {
        await _saveCloudEntry(entry.copyWith(photoPath: photoPath), user);
      } catch (error) {
        try {
          await SupabaseBackend.client.storage.from('plant-photos').remove([
            photoPath,
          ]);
        } catch (cleanupError) {
          throw StateError(
            'Could not save the observation ($error), and its uploaded photo '
            'could not be removed ($cleanupError).',
          );
        }
        rethrow;
      }
      return;
    }

    final savedEntry = photoBytes == null
        ? entry
        : entry.copyWith(photoDataBase64: base64Encode(photoBytes));
    final updatedEntries = [savedEntry, ...growthEntries.value]
      ..sort((a, b) => b.date.compareTo(a.date));
    final encoded = jsonEncode(
      updatedEntries.map((item) => item.toJson()).toList(),
    );
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_entriesKey, encoded);
    if (!saved) {
      throw StateError('The growth entry could not be saved to this device.');
    }
    growthEntries.value = List.unmodifiable(updatedEntries);
  }

  Future<void> _saveCloudEntry(GrowthEntry entry, User user) async {
    final client = SupabaseBackend.client;
    final plant = await client
        .from('plants')
        .upsert({
          'owner_id': user.id,
          'common_name': entry.plantName.trim(),
        }, onConflict: 'owner_id,common_name')
        .select('id')
        .single();
    final plantId = plant['id'] as String;
    final careActivity = _databaseActivity(entry.activity);
    late final GrowthEntry savedEntry;
    if (careActivity != null) {
      final saved = await client
          .from('care_activities')
          .insert({
            'owner_id': user.id,
            'plant_id': plantId,
            'activity': careActivity,
            'notes': entry.notes,
            'occurred_at': entry.date.toUtc().toIso8601String(),
          })
          .select('id, occurred_at')
          .single();
      savedEntry = GrowthEntry(
        id: saved['id'] as String,
        plantName: entry.plantName.trim(),
        activity: _displayActivity(careActivity),
        date: DateTime.parse(saved['occurred_at'] as String).toLocal(),
        notes: entry.notes,
      );
      if (!gardenPlantNames.value.contains(entry.plantName.trim())) {
        gardenPlantNames.value = List.unmodifiable([
          ...gardenPlantNames.value,
          entry.plantName.trim(),
        ]);
      }
    } else {
      final saved = await client
          .from('growth_entries')
          .insert({
            'owner_id': user.id,
            'plant_id': plantId,
            'observed_on':
                '${entry.date.year.toString().padLeft(4, '0')}-'
                '${entry.date.month.toString().padLeft(2, '0')}-'
                '${entry.date.day.toString().padLeft(2, '0')}',
            'height_cm': entry.heightCm,
            'leaf_count': entry.leafCount,
            'notes': entry.notes,
            'image_path': entry.photoPath,
          })
          .select('id, observed_on')
          .single();
      savedEntry = GrowthEntry(
        id: saved['id'] as String,
        plantName: entry.plantName.trim(),
        activity: entry.activity,
        date: DateTime.parse(saved['observed_on'] as String),
        notes: entry.notes,
        heightCm: entry.heightCm,
        leafCount: entry.leafCount,
        photoPath: entry.photoPath,
      );
      if (!gardenPlantNames.value.contains(entry.plantName.trim())) {
        gardenPlantNames.value = List.unmodifiable([
          ...gardenPlantNames.value,
          entry.plantName.trim(),
        ]);
      }
    }
    growthEntries.value = List.unmodifiable(
      ([savedEntry, ...growthEntries.value]
        ..sort((a, b) => b.date.compareTo(a.date))),
    );
  }

  static String? _databaseActivity(String activity) =>
      switch (activity.trim().toLowerCase()) {
        'watered' => 'watered',
        'fertilized' => 'fertilized',
        'pruned' => 'pruned',
        'repotted' => 'repotted',
        _ => null,
      };

  static String _displayActivity(String activity) => switch (activity) {
    'watered' => 'Watered',
    'fertilized' => 'Fertilized',
    'pruned' => 'Pruned',
    'repotted' => 'Repotted',
    _ => 'Other',
  };

  static String? _imageContentType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  Future<void> clearPersonalData() async {
    final preferences = await SharedPreferences.getInstance();
    final gardenRemoved = await preferences.remove(_gardenKey);
    final gardenDetailsRemoved = await preferences.remove(_gardenDetailsKey);
    final entriesRemoved = await preferences.remove(_entriesKey);
    final careKey = _careTasksStorageKey(_activeScope ?? 'device');
    final careTasksRemoved =
        !preferences.containsKey(careKey) || await preferences.remove(careKey);
    if (!gardenRemoved ||
        !gardenDetailsRemoved ||
        !entriesRemoved ||
        !careTasksRemoved) {
      throw StateError(
        'Local garden data could not be removed from this device.',
      );
    }

    gardenPlantNames.value = const [];
    gardenPlantDetails.value = const {};
    growthEntries.value = const [];
    completedCareTasks.value = const [];
    retryLoad();
  }
}
