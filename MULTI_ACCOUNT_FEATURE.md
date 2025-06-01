# Multi-Account Feature Documentation

## Overview

The Immich Flutter app now supports multiple accounts, allowing you to connect to different Immich servers and easily switch between them. You can add multiple accounts (each with their own URL and API key) and switch between them seamlessly.

## Features

### ✨ **Multi-Account Management**
- Add multiple Immich accounts with different servers
- Each account has its own name, server URL, and API key
- Easy switching between accounts with a single tap
- Visual indicators showing which account is currently active

### 🔄 **Account Switching**
- Instant switching between configured accounts
- No need to re-enter credentials
- Last used timestamps for each account
- Active account shown in the app header

### ⚙️ **Account Settings**
- Add new accounts through a dedicated management screen
- Edit existing account details (name, URL, API key)
- Remove unused accounts
- Test connection before saving

### 🔒 **Security**
- API keys are securely stored using Hive local database
- Keys are masked in the UI for security
- Each account's credentials are isolated

## How to Use

### Adding Your First Account

1. **Open the app** - If no accounts are configured, you'll see an "Add Account" button
2. **Tap the account icon** in the app bar or go to Settings
3. **Tap "Manage Accounts"**
4. **Tap the "+" button** to add a new account
5. **Fill in the details:**
   - **Account Name**: A friendly name (e.g., "Home Server", "Work Immich")
   - **Server URL**: Your Immich server URL (e.g., `https://immich.example.com`)
   - **API Key**: Your Immich API key
6. **Test Connection** to verify the settings
7. **Save** the account

### Adding Additional Accounts

1. **Go to Settings** → **Manage Accounts**
2. **Tap the "+" button**
3. **Enter the new account details**
4. **Save** the account

### Switching Between Accounts

#### Method 1: From App Bar
1. **Tap the account avatar** in the top-right corner
2. **Select "Account: [Name]"** from the dropdown
3. **Choose the account** you want to switch to

#### Method 2: From Account Management
1. **Go to Settings** → **Manage Accounts**
2. **Tap on any account** in the list
3. **Or use the menu** (⋮) → **"Switch to this account"**

### Editing Account Details

1. **Go to Settings** → **Manage Accounts**
2. **Tap the menu** (⋮) next to the account
3. **Select "Edit"**
4. **Modify the details** and save

### Removing an Account

1. **Go to Settings** → **Manage Accounts**
2. **Tap the menu** (⋮) next to the account
3. **Select "Remove"**
4. **Confirm** the removal

## User Interface

### App Bar Indicators
- **Account name** is displayed under the screen title
- **Account avatar** shows current account status
- **Green checkmark** indicates active account in lists

### Account Management Screen
- **Active Account card** at the top shows current account
- **Account list** with last used timestamps
- **Visual indicators** for active vs inactive accounts
- **Context menus** for quick actions

### Settings Integration
- **Quick Configuration** section for editing current account
- **Account Management** button for full account control
- **Active account display** with server URL

## Migration from Single Account

If you were using the app before this update:
- Your existing account will be automatically migrated
- It will be named "Default Account"
- All your settings and data remain intact
- You can rename it or add additional accounts

## Technical Details

### Data Storage
- Accounts are stored using **Hive** local database
- Each account has a unique ID based on URL+API key hash
- Active account ID stored in SharedPreferences
- Old SharedPreferences settings are automatically migrated

### Account Structure
```dart
class Account {
  String id;           // Unique identifier
  String name;         // Display name
  String baseUrl;      // Server URL
  String apiKey;       // API key
  bool isActive;       // Current account flag
  DateTime createdAt;  // Creation timestamp
  DateTime lastUsed;   // Last access timestamp
}
```

### Security Considerations
- API keys are stored locally and never transmitted except to their respective servers
- Each account maintains separate authentication
- No cross-account data sharing
- Account switching clears cached data appropriately

## Troubleshooting

### Connection Issues
- Verify server URL includes `http://` or `https://`
- Check API key is valid and has proper permissions
- Use "Test Connection" before saving accounts
- Ensure server is accessible from your device

### Account Switching Problems
- Try refreshing the account list
- Check if account credentials are still valid
- Remove and re-add problematic accounts

### Migration Issues
- Old settings should migrate automatically
- If not, manually add your account details
- Previous data and cache will be preserved

## Future Enhancements

Planned features for future releases:
- Account sync status indicators
- Quick account switcher widget
- Account-specific settings and preferences
- Import/export account configurations
- Account groups and organization features

## Support

If you encounter issues with the multi-account feature:
1. Check the connection to your Immich server
2. Verify API keys are correct
3. Try removing and re-adding accounts
4. Check server logs for authentication errors
5. Report bugs with detailed logs and steps to reproduce 