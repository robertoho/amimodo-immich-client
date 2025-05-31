import 'package:flutter/material.dart';
import '../services/immich_api_service.dart';

class SettingsScreen extends StatefulWidget {
  final ImmichApiService apiService;

  const SettingsScreen({super.key, required this.apiService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _isLoading = false;
  String? _connectionStatus;
  bool _isApiKeyPlaceholder = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() async {
    await widget.apiService.loadSettings();

    // Load the base URL if it exists
    if (widget.apiService.baseUrl != null) {
      _baseUrlController.text = widget.apiService.baseUrl!;
    }

    // For security, don't show the actual API key, but show if one is configured
    if (widget.apiService.hasApiKey) {
      _apiKeyController.text = '••••••••••••••••'; // Show placeholder
      _isApiKeyPlaceholder = true;
    }

    setState(() {});
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isLoading = true;
      _connectionStatus = null;
    });

    try {
      // First save the settings temporarily so we can test
      await widget.apiService.saveSettings(
        _baseUrlController.text.trim(),
        _isApiKeyPlaceholder ? '' : _apiKeyController.text.trim(),
      );

      // Run debug endpoints
      await widget.apiService.debugApiEndpoints();

      final bool isConnected = await widget.apiService.testConnection();
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

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        // If the field contains the placeholder, keep the existing API key
        final apiKeyToSave =
            _isApiKeyPlaceholder ? null : _apiKeyController.text.trim();

        if (apiKeyToSave != null) {
          await widget.apiService.saveSettings(
            _baseUrlController.text.trim(),
            apiKeyToSave,
          );
        } else {
          // Only update the base URL, keep existing API key
          await widget.apiService.saveSettings(
            _baseUrlController.text.trim(),
            '', // This will be handled in the service to preserve existing key
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Settings saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving settings: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Padding(
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 16.0 + MediaQuery.of(context).padding.top + kToolbarHeight,
          bottom: 16.0,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Immich Settings',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server Configuration',
                        style: Theme.of(context).textTheme.headlineSmall,
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
                          // Clear placeholder when user taps to edit
                          if (_isApiKeyPlaceholder) {
                            _apiKeyController.clear();
                            setState(() {
                              _isApiKeyPlaceholder = false;
                            });
                          }
                        },
                        validator: (value) {
                          if ((value == null || value.isEmpty) &&
                              !widget.apiService.hasApiKey) {
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
                    padding: const EdgeInsets.all(16.0),
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
                          : const Icon(Icons.wifi_protected_setup),
                      label: const Text('Test Connection'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveSettings,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Save Settings'),
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
