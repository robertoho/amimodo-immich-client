import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/immich_asset.dart';
import '../models/immich_album.dart';

class ImmichApiService {
  static const String _baseUrlKey = 'immich_base_url';
  static const String _apiKeyKey = 'immich_api_key';

  String? _baseUrl;
  String? _apiKey;

  ImmichApiService();

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_baseUrlKey);
    _apiKey = prefs.getString(_apiKeyKey);
  }

  Future<void> saveSettings(String baseUrl, String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, baseUrl);

    // Only update API key if it's not empty (preserve existing key)
    if (apiKey.isNotEmpty) {
      await prefs.setString(_apiKeyKey, apiKey);
      _apiKey = apiKey;
    }

    _baseUrl = baseUrl;
  }

  bool get isConfigured => _baseUrl != null && _apiKey != null;

  String? get baseUrl => _baseUrl;

  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': _apiKey ?? '',
      };

  Future<Map<String, dynamic>> searchAssets({
    int page = 1,
    int size = 100,
    String order = 'desc',
    bool? isFavorite,
    String? type, // IMAGE, VIDEO, AUDIO, OTHER
    DateTime? createdAfter,
    DateTime? createdBefore,
    DateTime? takenAfter,
    DateTime? takenBefore,
    bool? isNotInAlbum,
    bool? withExif = false,
    String? city,
    String? country,
  }) async {
    if (!isConfigured) {
      throw Exception('API not configured. Please set base URL and API key.');
    }

    final uri = Uri.parse('$_baseUrl/api/search/assets');

    try {
      final requestBody = <String, dynamic>{
        'page': page,
        'size': size,
        'order': order,
      };

      // Add optional filters
      if (isFavorite != null) requestBody['isFavorite'] = isFavorite;
      if (type != null) requestBody['type'] = type;
      if (createdAfter != null)
        requestBody['createdAfter'] = createdAfter.toIso8601String();
      if (createdBefore != null)
        requestBody['createdBefore'] = createdBefore.toIso8601String();
      if (takenAfter != null)
        requestBody['takenAfter'] = takenAfter.toIso8601String();
      if (takenBefore != null)
        requestBody['takenBefore'] = takenBefore.toIso8601String();
      if (isNotInAlbum != null) requestBody['isNotInAlbum'] = isNotInAlbum;
      if (withExif != null) requestBody['withExif'] = withExif;
      if (city != null) requestBody['city'] = city;
      if (country != null) requestBody['country'] = country;

      print('🔍 SearchAssets request: ${json.encode(requestBody)}');

      final response = await http.post(
        uri,
        headers: _headers,
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        print('✅ SearchAssets response: ${responseData.keys}');
        return responseData;
      } else {
        throw Exception(
            'Failed to search assets from $uri: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error searching assets from $uri: $e');
    }
  }

  Future<List<ImmichAsset>> getAssets({
    int page = 1,
    int size = 100,
    String order = 'desc',
    bool? isFavorite,
    String? type,
    DateTime? createdAfter,
    DateTime? createdBefore,
  }) async {
    final searchResult = await searchAssets(
      page: page,
      size: size,
      order: order,
      isFavorite: isFavorite,
      type: type,
      createdAfter: createdAfter,
      createdBefore: createdBefore,
    );

    final assets = searchResult['assets'] as Map<String, dynamic>?;
    final List<dynamic> jsonList = assets?['items'] ?? [];
    return jsonList.map((json) => ImmichAsset.fromJson(json)).toList();
  }

  String getThumbnailUrl(String assetId) {
    if (!isConfigured) return '';
    final url = '$_baseUrl/api/assets/$assetId/thumbnail';
    print('🔗 Generated thumbnail URL: $url');
    return url;
  }

  String getThumbnailUrlFallback(String assetId) {
    if (!isConfigured) return '';
    final url = '$_baseUrl/api/assets/$assetId/view?size=thumbnail';
    print('🔗 Generated fallback thumbnail URL: $url');
    return url;
  }

  String getPreviewUrl(String assetId) {
    if (!isConfigured) return '';
    final url = '$_baseUrl/api/assets/$assetId/view?size=preview';
    print('🔗 Generated preview URL: $url');
    return url;
  }

  String getAssetUrl(String assetId) {
    if (!isConfigured) return '';
    final url = '$_baseUrl/api/assets/$assetId/original';
    print('🔗 Generated asset URL: $url');
    return url;
  }

  String getAssetUrlFallback(String assetId) {
    if (!isConfigured) return '';
    final url = '$_baseUrl/api/assets/$assetId/view?size=fullsize';
    print('🔗 Generated fallback asset URL: $url');
    return url;
  }

  Map<String, String> get authHeaders => _headers;

  Future<bool> testConnection() async {
    if (!isConfigured) return false;

    // Try multiple potential endpoints to find the correct one
    final endpointsToTry = [
      '/api/server/ping',
      '/api/server-info/ping',
      '/ping',
      '/api/auth/validateToken',
      '/api/server/version',
    ];

    for (final endpoint in endpointsToTry) {
      final uri = Uri.parse('$_baseUrl$endpoint');

      try {
        final response = await http.get(uri, headers: _headers);
        print('Testing $uri: ${response.statusCode}');

        if (response.statusCode == 200) {
          print('✅ Connection successful with $uri');
          return true;
        }
      } catch (e) {
        print('❌ Connection test failed for $uri: $e');
      }
    }

    return false;
  }

  Future<void> debugApiEndpoints() async {
    if (!isConfigured) return;

    print('🔍 Debugging API endpoints for base URL: $_baseUrl');

    // Test asset endpoints
    final assetEndpoints = [
      '/api/search/assets',
      '/api/search/metadata',
      '/api/assets',
      '/api/asset',
    ];

    for (final endpoint in assetEndpoints) {
      final uri = Uri.parse('$_baseUrl$endpoint');

      try {
        // Try GET first
        final getResponse = await http.get(uri, headers: _headers);
        print('GET $uri: ${getResponse.statusCode}');

        // Try POST if GET fails
        if (getResponse.statusCode == 404 || endpoint.contains('search')) {
          final postResponse = await http.post(
            uri,
            headers: _headers,
            body: json.encode({'page': 1, 'size': 10}),
          );
          print('POST $uri: ${postResponse.statusCode}');

          if (postResponse.statusCode == 200 && endpoint.contains('metadata')) {
            final responseData = json.decode(postResponse.body);
            print('  - Metadata response keys: ${responseData.keys}');
          }
        }
      } catch (e) {
        print('Error testing $uri: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> getServerInfo() async {
    if (!isConfigured) return null;

    final uri = Uri.parse('$_baseUrl/api/server/version');

    try {
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('Server info failed for $uri: ${response.statusCode}');
      }
    } catch (e) {
      print('Server info error for $uri: $e');
    }
    return null;
  }

  Future<List<ImmichAlbum>> getAllAlbums({bool? shared}) async {
    if (!isConfigured) {
      throw Exception('API not configured. Please set base URL and API key.');
    }

    final uri = Uri.parse('$_baseUrl/api/albums').replace(
      queryParameters: shared != null ? {'shared': shared.toString()} : null,
    );

    try {
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => ImmichAlbum.fromJson(json)).toList();
      } else {
        throw Exception(
            'Failed to load albums from $uri: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching albums from $uri: $e');
    }
  }

  String getAlbumThumbnailUrl(String? assetId) {
    if (!isConfigured || assetId == null) return '';
    final url = '$_baseUrl/api/assets/$assetId/thumbnail';
    print('🔗 Generated album thumbnail URL: $url');
    return url;
  }

  String getAlbumThumbnailUrlFallback(String? assetId) {
    if (!isConfigured || assetId == null) return '';
    final url = '$_baseUrl/api/assets/$assetId/view?size=thumbnail';
    print('🔗 Generated album fallback thumbnail URL: $url');
    return url;
  }

  Future<List<ImmichAsset>> getAlbumAssets(String albumId) async {
    if (!isConfigured) {
      throw Exception('API not configured. Please set base URL and API key.');
    }

    final uri = Uri.parse('$_baseUrl/api/albums/$albumId');

    try {
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<dynamic> jsonList = responseData['assets'] ?? [];
        return jsonList.map((json) => ImmichAsset.fromJson(json)).toList();
      } else {
        throw Exception(
            'Failed to load album assets from $uri: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching album assets from $uri: $e');
    }
  }

  Future<String?> getWorkingThumbnailUrl(String assetId) async {
    if (!isConfigured) return null;

    // Test different thumbnail endpoints to find the working one
    final endpointsToTry = [
      '$_baseUrl/api/assets/$assetId/view?size=thumbnail',
      '$_baseUrl/api/assets/$assetId/thumbnail',
      '$_baseUrl/api/assets/$assetId/view?size=preview',
      '$_baseUrl/api/asset/$assetId/thumbnail',
    ];

    for (final url in endpointsToTry) {
      try {
        final response = await http.head(
          Uri.parse(url),
          headers: _headers,
        );

        print('Testing thumbnail URL $url: ${response.statusCode}');

        if (response.statusCode == 200) {
          print('✅ Working thumbnail URL found: $url');
          return url;
        }
      } catch (e) {
        print('❌ Error testing $url: $e');
      }
    }

    print('❌ No working thumbnail URL found for asset $assetId');
    return null;
  }

  Future<Map<String, dynamic>> searchMetadata({
    int page = 1,
    int size = 100,
    String order = 'desc',
    bool? isFavorite,
    bool? isOffline,
    bool? isTrashed,
    bool? isArchived,
    bool? withDeleted = false,
    bool? withArchived = false,
    String? type, // IMAGE, VIDEO, AUDIO, OTHER
    DateTime? createdAfter,
    DateTime? createdBefore,
    DateTime? takenAfter,
    DateTime? takenBefore,
    DateTime? trashedAfter,
    DateTime? trashedBefore,
    String? city,
    String? country,
    String? make,
    String? model,
    String? lensModel,
    bool? withExif = false,
    bool? withPeople = false,
    List<String>? personIds,
    List<String>? tagIds,
  }) async {
    if (!isConfigured) {
      throw Exception('API not configured. Please set base URL and API key.');
    }

    final uri = Uri.parse('$_baseUrl/api/search/metadata');

    try {
      final requestBody = <String, dynamic>{
        'page': page,
        'size': size,
        'order': order,
      };

      // Add optional filters
      if (isFavorite != null) requestBody['isFavorite'] = isFavorite;
      if (isOffline != null) requestBody['isOffline'] = isOffline;
      if (isTrashed != null) requestBody['isTrashed'] = isTrashed;
      if (isArchived != null) requestBody['isArchived'] = isArchived;
      if (withDeleted != null) requestBody['withDeleted'] = withDeleted;
      if (withArchived != null) requestBody['withArchived'] = withArchived;
      if (type != null) requestBody['type'] = type;
      if (createdAfter != null)
        requestBody['createdAfter'] = createdAfter.toIso8601String();
      if (createdBefore != null)
        requestBody['createdBefore'] = createdBefore.toIso8601String();
      if (takenAfter != null)
        requestBody['takenAfter'] = takenAfter.toIso8601String();
      if (takenBefore != null)
        requestBody['takenBefore'] = takenBefore.toIso8601String();
      if (trashedAfter != null)
        requestBody['trashedAfter'] = trashedAfter.toIso8601String();
      if (trashedBefore != null)
        requestBody['trashedBefore'] = trashedBefore.toIso8601String();
      if (city != null) requestBody['city'] = city;
      if (country != null) requestBody['country'] = country;
      if (make != null) requestBody['make'] = make;
      if (model != null) requestBody['model'] = model;
      if (lensModel != null) requestBody['lensModel'] = lensModel;
      if (withExif != null) requestBody['withExif'] = withExif;
      if (withPeople != null) requestBody['withPeople'] = withPeople;
      if (personIds != null && personIds.isNotEmpty)
        requestBody['personIds'] = personIds;
      if (tagIds != null && tagIds.isNotEmpty) requestBody['tagIds'] = tagIds;

      print('🔍 SearchMetadata request: ${json.encode(requestBody)}');

      final response = await http.post(
        uri,
        headers: _headers,
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        print('✅ SearchMetadata response keys: ${responseData.keys}');
        if (responseData.containsKey('assets')) {
          print('  - Assets structure: ${responseData['assets']?.runtimeType}');
          if (responseData['assets'] is Map) {
            final assetsMap = responseData['assets'] as Map<String, dynamic>;
            print('  - Assets keys: ${assetsMap.keys}');
            if (assetsMap.containsKey('items')) {
              print(
                  '  - Items count: ${(assetsMap['items'] as List?)?.length ?? 0}');
            }
          }
        }
        return responseData;
      } else {
        throw Exception(
            'Failed to search metadata from $uri: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error searching metadata from $uri: $e');
    }
  }

  Future<List<ImmichAsset>> getOfflineAssets({
    int page = 1,
    int size = 100,
    bool withArchived = true,
    bool withDeleted = true,
  }) async {
    final searchResult = await searchMetadata(
      page: page,
      size: size,
      isOffline: true,
      withArchived: withArchived,
      withDeleted: withDeleted,
    );

    final assets = searchResult['assets'] as Map<String, dynamic>?;
    final List<dynamic> jsonList = assets?['items'] ?? [];
    return jsonList.map((json) => ImmichAsset.fromJson(json)).toList();
  }

  Future<List<ImmichAsset>> getTrashedAssets({
    int page = 1,
    int size = 100,
    DateTime? trashedAfter,
    DateTime? trashedBefore,
  }) async {
    final searchResult = await searchMetadata(
      page: page,
      size: size,
      isTrashed: true,
      withDeleted: true,
      trashedAfter: trashedAfter,
      trashedBefore: trashedBefore,
    );

    final assets = searchResult['assets'] as Map<String, dynamic>?;
    final List<dynamic> jsonList = assets?['items'] ?? [];
    return jsonList.map((json) => ImmichAsset.fromJson(json)).toList();
  }

  Future<List<Map<String, dynamic>>> addAssetsToAlbum(
      String albumId, List<String> assetIds) async {
    if (!isConfigured) {
      throw Exception('API not configured. Please set base URL and API key.');
    }

    final uri = Uri.parse('$_baseUrl/api/albums/$albumId/assets');

    try {
      final requestBody = {
        'ids': assetIds,
      };

      print('📝 Adding ${assetIds.length} assets to album $albumId');

      final response = await http.put(
        uri,
        headers: _headers,
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final List<dynamic> responseData = json.decode(response.body);
        final results = responseData.cast<Map<String, dynamic>>();

        // Log results for debugging
        final successful = results.where((r) => r['success'] == true).length;
        final failed = results.length - successful;
        print('✅ Album operation: $successful successful, $failed failed');

        if (failed > 0) {
          final errors = results
              .where((r) => r['success'] != true)
              .map((r) => r['error'])
              .toList();
          print('❌ Errors: $errors');

          // Log detailed error analysis for debugging
          for (final result in results.where((r) => r['success'] != true)) {
            final error = result['error']?.toString() ?? 'unknown error';
            final isDuplicate = error.toLowerCase().contains('duplicate') ||
                error.toLowerCase().contains('already') ||
                error.toLowerCase().contains('exists');
            print(
                '📋 Asset ${result['id'] ?? 'unknown'}: $error (duplicate: $isDuplicate)');
          }
        }

        return results;
      } else {
        throw Exception(
            'Failed to add assets to album $albumId: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error adding assets to album $albumId: $e');
    }
  }

  Future<List<Map<String, dynamic>>> removeAssetFromAlbum(
      String albumId, List<String> assetIds) async {
    if (!isConfigured) {
      throw Exception('API not configured. Please set base URL and API key.');
    }

    final uri = Uri.parse('$_baseUrl/api/albums/$albumId/assets');

    try {
      final requestBody = {
        'ids': assetIds,
      };

      print('🗑️ Removing ${assetIds.length} assets from album $albumId');

      final response = await http.delete(
        uri,
        headers: _headers,
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final List<dynamic> responseData = json.decode(response.body);
        final results = responseData.cast<Map<String, dynamic>>();

        // Log results for debugging
        final successful = results.where((r) => r['success'] == true).length;
        final failed = results.length - successful;
        print(
            '✅ Album removal operation: $successful successful, $failed failed');

        if (failed > 0) {
          final errors = results
              .where((r) => r['success'] != true)
              .map((r) => r['error'])
              .toList();
          print('❌ Removal errors: $errors');

          // Log detailed error analysis for debugging
          for (final result in results.where((r) => r['success'] != true)) {
            final error = result['error']?.toString() ?? 'unknown error';
            print('📋 Asset ${result['id'] ?? 'unknown'}: $error');
          }
        }

        return results;
      } else {
        throw Exception(
            'Failed to remove assets from album $albumId: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error removing assets from album $albumId: $e');
    }
  }
}
