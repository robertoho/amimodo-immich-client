import 'package:hive_flutter/hive_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/account.dart';

class AccountManager {
  static const String _accountsBoxName = 'accounts';
  static const String _activeAccountKey = 'active_account_id';

  Box<Account>? _accountsBox;
  Account? _activeAccount;

  static final AccountManager _instance = AccountManager._internal();
  factory AccountManager() => _instance;
  AccountManager._internal();

  Future<void> initialize() async {
    try {
      _accountsBox = await Hive.openBox<Account>(_accountsBoxName);
      await _loadActiveAccount();
    } catch (e) {
      print('Error initializing AccountManager: $e');
    }
  }

  Future<void> _loadActiveAccount() async {
    if (_accountsBox == null) return;

    // Load active account ID from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final activeAccountId = prefs.getString(_activeAccountKey);

    if (activeAccountId != null) {
      _activeAccount = _accountsBox!.get(activeAccountId);
    }

    // If no active account or active account doesn't exist, try to set the first one
    if (_activeAccount == null && _accountsBox!.values.isNotEmpty) {
      final firstAccount = _accountsBox!.values.first;
      await setActiveAccount(firstAccount.id);
    }
  }

  List<Account> getAllAccounts() {
    if (_accountsBox == null) return [];
    return _accountsBox!.values.toList()
      ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
  }

  Account? getActiveAccount() {
    return _activeAccount;
  }

  Future<void> addAccount({
    required String name,
    required String baseUrl,
    required String apiKey,
  }) async {
    if (_accountsBox == null) throw Exception('AccountManager not initialized');

    // Create a unique ID for the account
    final accountId = _generateAccountId(baseUrl, apiKey);

    // Check if account already exists
    if (_accountsBox!.containsKey(accountId)) {
      throw Exception('Account already exists');
    }

    final account = Account(
      id: accountId,
      name: name,
      baseUrl: baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl,
      apiKey: apiKey,
      isActive: _accountsBox!.isEmpty, // First account is active by default
    );

    await _accountsBox!.put(accountId, account);

    // If this is the first account, make it active
    if (_activeAccount == null) {
      await setActiveAccount(accountId);
    }
  }

  Future<void> updateAccount(
    String accountId, {
    String? name,
    String? baseUrl,
    String? apiKey,
  }) async {
    if (_accountsBox == null) throw Exception('AccountManager not initialized');

    final account = _accountsBox!.get(accountId);
    if (account == null) throw Exception('Account not found');

    final updatedAccount = account.copyWith(
      name: name,
      baseUrl: baseUrl?.endsWith('/') == true
          ? baseUrl!.substring(0, baseUrl.length - 1)
          : baseUrl,
      apiKey: apiKey,
      lastUsed: DateTime.now(),
    );

    await _accountsBox!.put(accountId, updatedAccount);

    // Update active account if it's the one being updated
    if (_activeAccount?.id == accountId) {
      _activeAccount = updatedAccount;
    }
  }

  Future<void> removeAccount(String accountId) async {
    if (_accountsBox == null) throw Exception('AccountManager not initialized');

    await _accountsBox!.delete(accountId);

    // If the removed account was active, switch to another account
    if (_activeAccount?.id == accountId) {
      _activeAccount = null;

      // Remove active account ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeAccountKey);

      // Try to set another account as active
      if (_accountsBox!.values.isNotEmpty) {
        final firstAccount = _accountsBox!.values.first;
        await setActiveAccount(firstAccount.id);
      }
    }
  }

  Future<void> setActiveAccount(String accountId) async {
    if (_accountsBox == null) throw Exception('AccountManager not initialized');

    final account = _accountsBox!.get(accountId);
    if (account == null) throw Exception('Account not found');

    // Update last used time
    final updatedAccount = account.copyWith(lastUsed: DateTime.now());
    await _accountsBox!.put(accountId, updatedAccount);

    _activeAccount = updatedAccount;

    // Store active account ID as a separate preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeAccountKey, accountId);

    print('✅ Switched to account: ${account.name} (${account.baseUrl})');
  }

  bool hasAccounts() {
    return _accountsBox?.isNotEmpty ?? false;
  }

  bool isConfigured() {
    return _activeAccount != null &&
        _activeAccount!.baseUrl.isNotEmpty &&
        _activeAccount!.apiKey.isNotEmpty;
  }

  String? getActiveBaseUrl() {
    return _activeAccount?.baseUrl;
  }

  String? getActiveApiKey() {
    return _activeAccount?.apiKey;
  }

  String? getActiveName() {
    return _activeAccount?.name;
  }

  String _generateAccountId(String baseUrl, String apiKey) {
    final combined = '$baseUrl:$apiKey';
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // Use first 16 characters
  }

  // Migration method to import from old SharedPreferences
  Future<void> migrateFromSharedPreferences() async {
    try {
      // This will be called if no accounts exist but old settings do
      final prefs = await SharedPreferences.getInstance();

      final oldBaseUrl = prefs.getString('immich_base_url');
      final oldApiKey = prefs.getString('immich_api_key');

      if (oldBaseUrl != null &&
          oldApiKey != null &&
          oldBaseUrl.isNotEmpty &&
          oldApiKey.isNotEmpty) {
        // Create account from old settings
        await addAccount(
          name: 'Default Account',
          baseUrl: oldBaseUrl,
          apiKey: oldApiKey,
        );

        // Clean up old settings
        await prefs.remove('immich_base_url');
        await prefs.remove('immich_api_key');

        print('✅ Migrated account from SharedPreferences');
      }
    } catch (e) {
      print('Migration error: $e');
    }
  }
}
