import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/home_screen.dart';
import 'services/grid_scale_service.dart';
import 'services/thumbnail_cache_service.dart';
import 'models/thumbnail_cache_entry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();

  // Register Hive adapters
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(ThumbnailCacheEntryAdapter());
  }

  // Initialize services
  await GridScaleService().initialize();

  final cacheService = ThumbnailCacheService();
  await cacheService.initialize();

  // Test Hive connection
  final hiveWorking = await cacheService.testHiveConnection();
  debugPrint(hiveWorking
      ? '✅ Hive database working correctly'
      : '❌ Hive database test failed');

  runApp(const ImmichApp());
}

class ImmichApp extends StatelessWidget {
  const ImmichApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Immich Flutter App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
