import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/repositories/runtime_lock_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Database competingDb;
  late String databasePath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    databasePath = '${await databaseFactoryFfi.getDatabasesPath()}/totals.db';
    await databaseFactoryFfi.deleteDatabase(databasePath);
    db = await DatabaseHelper.instance.database;
    competingDb = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
  });

  tearDown(() async {
    if (competingDb.isOpen) await competingDb.close();
    if (db.isOpen) await DatabaseHelper.instance.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test('simultaneous backup connections can acquire only one SQLite lease',
      () async {
    final firstRepository = RuntimeLockRepository(
      databaseProvider: () async => db,
      ownerIdFactory: () => 'periodic-worker',
    );
    final secondRepository = RuntimeLockRepository(
      databaseProvider: () async => competingDb,
      ownerIdFactory: () => 'summary-worker',
    );

    final leases = await Future.wait([
      firstRepository.tryAcquire('telegram_backup'),
      secondRepository.tryAcquire('telegram_backup'),
    ]);
    final acquired = leases.whereType<RuntimeLockLease>().toList();

    expect(acquired, hasLength(1));

    final blockedRepository = acquired.single.owner == 'periodic-worker'
        ? secondRepository
        : firstRepository;
    expect(
      await blockedRepository.tryAcquire('telegram_backup'),
      isNull,
    );

    await firstRepository.release(acquired.single);
    final nextLease = await blockedRepository.tryAcquire('telegram_backup');
    expect(nextLease, isNotNull);
  });

  test('expired leases recover without allowing an old owner to release anew',
      () async {
    var now = DateTime.utc(2026, 7, 29, 20);
    final firstRepository = RuntimeLockRepository(
      databaseProvider: () async => db,
      clock: () => now,
      ownerIdFactory: () => 'stale-worker',
    );
    final secondRepository = RuntimeLockRepository(
      databaseProvider: () async => competingDb,
      clock: () => now,
      ownerIdFactory: () => 'replacement-worker',
    );
    final firstLease = await firstRepository.tryAcquire(
      'telegram_backup',
      ttl: const Duration(minutes: 1),
    );
    expect(firstLease, isNotNull);

    now = now.add(const Duration(minutes: 2));
    final replacementLease = await secondRepository.tryAcquire(
      'telegram_backup',
      ttl: const Duration(minutes: 1),
    );
    expect(replacementLease?.owner, 'replacement-worker');

    await firstRepository.release(firstLease!);
    expect(
      await firstRepository.tryAcquire('telegram_backup'),
      isNull,
    );
  });
}
