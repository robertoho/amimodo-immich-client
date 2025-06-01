import 'package:flutter/material.dart';
import '../services/account_manager.dart';
import '../services/immich_api_service.dart';
import '../models/account.dart';

class AccountManagementScreen extends StatefulWidget {
  final ImmichApiService apiService;

  const AccountManagementScreen({super.key, required this.apiService});

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final AccountManager _accountManager = AccountManager();
  List<Account> _accounts = [];
  Account? _activeAccount;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  void _loadAccounts() async {
    setState(() => _isLoading = true);

    try {
      await _accountManager.initialize();
      _accounts = _accountManager.getAllAccounts();
      _activeAccount = _accountManager.getActiveAccount();
    } catch (e) {
      print('Error loading accounts: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _switchAccount(String accountId) async {
    setState(() => _isLoading = true);

    try {
      await _accountManager.setActiveAccount(accountId);
      _loadAccounts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account switched successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error switching account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeAccount(String accountId) async {
    final account = _accounts.firstWhere((acc) => acc.id == accountId);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Account'),
        content: Text('Are you sure you want to remove "${account.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);

      try {
        await _accountManager.removeAccount(accountId);
        _loadAccounts();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account "${account.name}" removed'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error removing account: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addOrEditAccount({Account? account}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AddEditAccountScreen(
          account: account,
          accountManager: _accountManager,
        ),
      ),
    );

    if (result == true) {
      _loadAccounts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Management'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_activeAccount != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_circle,
                                color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Active Account',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _activeAccount!.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _activeAccount!.baseUrl,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _accounts.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.account_circle_outlined,
                                size: 80,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No accounts configured',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Add your first Immich account to get started',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _accounts.length,
                          itemBuilder: (context, index) {
                            final account = _accounts[index];
                            final isActive = account.id == _activeAccount?.id;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isActive
                                      ? Colors.green
                                      : Colors.grey.shade300,
                                  child: Icon(
                                    isActive
                                        ? Icons.check
                                        : Icons.account_circle,
                                    color: isActive
                                        ? Colors.white
                                        : Colors.grey.shade600,
                                  ),
                                ),
                                title: Text(
                                  account.name,
                                  style: TextStyle(
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(account.baseUrl),
                                    Text(
                                      'Last used: ${_formatDate(account.lastUsed)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'switch':
                                        if (!isActive)
                                          _switchAccount(account.id);
                                        break;
                                      case 'edit':
                                        _addOrEditAccount(account: account);
                                        break;
                                      case 'remove':
                                        _removeAccount(account.id);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    if (!isActive)
                                      const PopupMenuItem(
                                        value: 'switch',
                                        child: Row(
                                          children: [
                                            Icon(Icons.swap_horiz),
                                            SizedBox(width: 8),
                                            Text('Switch to this account'),
                                          ],
                                        ),
                                      ),
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit),
                                          SizedBox(width: 8),
                                          Text('Edit'),
                                        ],
                                      ),
                                    ),
                                    if (_accounts.length > 1)
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete,
                                                color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Remove',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: isActive
                                    ? null
                                    : () => _switchAccount(account.id),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditAccount(),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }
}

class AddEditAccountScreen extends StatefulWidget {
  final Account? account;
  final AccountManager accountManager;

  const AddEditAccountScreen({
    super.key,
    this.account,
    required this.accountManager,
  });

  @override
  State<AddEditAccountScreen> createState() => _AddEditAccountScreenState();
}

class _AddEditAccountScreenState extends State<AddEditAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _isLoading = false;
  String? _connectionStatus;
  bool _isApiKeyPlaceholder = false;

  @override
  void initState() {
    super.initState();
    if (widget.account != null) {
      _nameController.text = widget.account!.name;
      _baseUrlController.text = widget.account!.baseUrl;
      _apiKeyController.text = '••••••••••••••••';
      _isApiKeyPlaceholder = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _connectionStatus = null;
    });

    try {
      // Create a temporary ImmichApiService to test connection
      final testApiService = ImmichApiService();
      await testApiService.saveSettings(
        _baseUrlController.text.trim(),
        _isApiKeyPlaceholder
            ? widget.account!.apiKey
            : _apiKeyController.text.trim(),
      );

      final bool isConnected = await testApiService.testConnection();
      setState(() {
        _connectionStatus =
            isConnected ? 'Connected successfully!' : 'Connection failed';
      });
    } catch (e) {
      setState(() {
        _connectionStatus = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();
      final baseUrl = _baseUrlController.text.trim();
      final apiKey = _isApiKeyPlaceholder
          ? widget.account!.apiKey
          : _apiKeyController.text.trim();

      if (widget.account != null) {
        // Update existing account
        await widget.accountManager.updateAccount(
          widget.account!.id,
          name: name,
          baseUrl: baseUrl,
          apiKey: apiKey,
        );
      } else {
        // Add new account
        await widget.accountManager.addAccount(
          name: name,
          baseUrl: baseUrl,
          apiKey: apiKey,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.account != null
                ? 'Account updated successfully!'
                : 'Account added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.account != null ? 'Edit Account' : 'Add Account'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account Information',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Account Name',
                          hintText: 'My Immich Server',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.label),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter an account name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _baseUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Server URL',
                          hintText: 'https://your-immich-server.com',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.language),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the server URL';
                          }
                          final uri = Uri.tryParse(value);
                          if (uri == null ||
                              !uri.hasScheme ||
                              (uri.scheme != 'http' && uri.scheme != 'https')) {
                            return 'Please enter a valid URL with http:// or https://';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _apiKeyController,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          hintText: 'Your Immich API key',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.key),
                          helperText: _isApiKeyPlaceholder
                              ? 'API key is already configured. Tap to change it.'
                              : null,
                        ),
                        obscureText: true,
                        onTap: () {
                          if (_isApiKeyPlaceholder) {
                            _apiKeyController.clear();
                            setState(() {
                              _isApiKeyPlaceholder = false;
                            });
                          }
                        },
                        validator: (value) {
                          if ((value == null || value.isEmpty) &&
                              !_isApiKeyPlaceholder) {
                            return 'Please enter your API key';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_connectionStatus != null)
                Card(
                  color: _connectionStatus!.contains('successfully')
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          _connectionStatus!.contains('successfully')
                              ? Icons.check_circle
                              : Icons.error,
                          color: _connectionStatus!.contains('successfully')
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_connectionStatus!)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _testConnection,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find),
                      label: const Text('Test Connection'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveAccount,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                          widget.account != null ? 'Update' : 'Add Account'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('How to get your API key:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text('1. Open your Immich web interface'),
                      Text('2. Go to Account Settings'),
                      Text('3. Navigate to API Keys section'),
                      Text('4. Create a new API key'),
                      Text('5. Copy and paste it here'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
