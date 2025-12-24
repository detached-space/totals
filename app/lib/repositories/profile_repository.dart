import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/profile.dart';

class ProfileRepository {
  Future<List<Profile>> getProfiles() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'profiles',
      orderBy: 'createdAt ASC',
    );

    return maps.map((map) {
      return Profile.fromJson({
        'id': map['id'],
        'name': map['name'],
        'createdAt': map['createdAt'],
        'updatedAt': map['updatedAt'],
      });
    }).toList();
  }

  Future<Profile?> getProfile(int id) async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'profiles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    return Profile.fromJson({
      'id': maps[0]['id'],
      'name': maps[0]['name'],
      'createdAt': maps[0]['createdAt'],
      'updatedAt': maps[0]['updatedAt'],
    });
  }

  Future<Profile?> getDefaultProfile() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'profiles',
      orderBy: 'createdAt ASC',
      limit: 1,
    );

    if (maps.isEmpty) return null;

    return Profile.fromJson({
      'id': maps[0]['id'],
      'name': maps[0]['name'],
      'createdAt': maps[0]['createdAt'],
      'updatedAt': maps[0]['updatedAt'],
    });
  }

  Future<int> saveProfile(Profile profile) async {
    final db = await DatabaseHelper.instance.database;
    
    if (profile.id == null) {
      // Insert new profile
      return await db.insert(
        'profiles',
        {
          'name': profile.name,
          'createdAt': profile.createdAt.toIso8601String(),
          'updatedAt': profile.updatedAt?.toIso8601String(),
        },
      );
    } else {
      // Update existing profile
      return await db.update(
        'profiles',
        {
          'name': profile.name,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [profile.id],
      );
    }
  }

  Future<void> deleteProfile(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'profiles',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> hasAnyProfiles() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM profiles');
    return (result.first['count'] as int) > 0;
  }

  Future<void> initializeDefaultProfile() async {
    final hasProfiles = await hasAnyProfiles();
    if (!hasProfiles) {
      final defaultProfile = Profile(
        name: 'Personal',
        createdAt: DateTime.now(),
      );
      final profileId = await saveProfile(defaultProfile);
      // Set as active profile
      await setActiveProfile(profileId);
    } else {
      // Ensure there's an active profile
      final activeId = await getActiveProfileId();
      if (activeId == null) {
        final profiles = await getProfiles();
        if (profiles.isNotEmpty && profiles.first.id != null) {
          await setActiveProfile(profiles.first.id!);
        }
      }
    }
  }

  Future<void> setActiveProfile(int profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_profile_id', profileId);
  }

  Future<int?> getActiveProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('active_profile_id');
  }

  Future<Profile?> getActiveProfile() async {
    final activeId = await getActiveProfileId();
    if (activeId == null) return null;
    return await getProfile(activeId);
  }
}

