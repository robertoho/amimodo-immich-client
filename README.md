# Immich Flutter App

A Flutter mobile and desktop application that connects to your Immich server and displays your photos in a beautiful, responsive grid layout.

## Features

- 🖼️ **Photo Grid View**: Browse your photos in a responsive masonry grid layout
- 🔍 **Photo Detail View**: Tap any photo to view it in full screen with zoom capabilities
- ⚙️ **Server Configuration**: Easy setup with your Immich server URL and API key
- 🔄 **Pull to Refresh**: Refresh your photo library with a simple pull gesture
- 📱 **Infinite Scroll**: Automatically loads more photos as you scroll
- ❤️ **Favorite Indicators**: See which photos are marked as favorites
- 🎥 **Video Support**: Distinguishes between photos and videos with visual indicators
- 📅 **Date Information**: Shows creation dates for each photo
- 💻 **Desktop Support**: Runs natively on macOS with responsive design

## Platform Support

- ✅ **iOS** - Mobile app experience
- ✅ **Android** - Mobile app experience  
- ✅ **macOS** - Desktop app experience with adaptive grid layout
- 🔄 **Windows** & **Linux** - Coming soon

## Screenshots

The app features a clean, modern interface with:
- Material Design 3 styling
- Responsive photo grid with staggered layout (2-4 columns based on screen size)
- Dark theme for photo viewing
- Intuitive settings screen with connection testing
- Native desktop window controls on macOS

## Setup Instructions

### Prerequisites

- A running Immich server
- Flutter development environment set up
- An Immich API key

### Getting Your Immich API Key

1. Open your Immich web interface
2. Go to **Account Settings**
3. Navigate to the **API Keys** section
4. Create a new API key
5. Copy the generated key for use in the app

### Installation

1. Clone this repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```

### Running the App

#### On macOS (Desktop):
```bash
flutter run -d macos
```

#### On iOS:
```bash
flutter run -d ios
```

#### On Android:
```bash
flutter run -d android
```

#### On Chrome (Web - for testing):
```bash
flutter run -d chrome
```

### Configuration

1. Open the app and tap/click the settings icon
2. Enter your Immich server URL (e.g., `https://your-immich-server.com`)
3. Enter your API key
4. Tap "Test Connection" to verify the connection
5. Save the settings

## macOS-Specific Features

- **Native Desktop App**: Runs as a native macOS application
- **Responsive Grid**: Automatically adjusts column count based on window size:
  - Small windows: 2 columns
  - Medium windows (>600px): 2 columns  
  - Large windows (>800px): 3 columns
  - Extra large windows (>1200px): 4 columns
- **Keyboard Shortcuts**: Standard macOS shortcuts supported
- **Window Management**: Resizable window with proper scaling

## Dependencies

- **http**: For API communication with Immich server
- **cached_network_image**: Efficient image loading and caching
- **flutter_staggered_grid_view**: Beautiful masonry grid layout
- **shared_preferences**: Persistent storage for server settings

## API Integration

The app integrates with the Immich API using the following endpoints:
- `/api/asset` - Fetching photo/video assets
- `/api/asset/thumbnail/{id}` - Loading photo thumbnails
- `/api/asset/file/{id}` - Loading full-resolution images
- `/api/server-info/ping` - Testing server connection

## Architecture

The app follows a clean architecture pattern:

```
lib/
├── models/           # Data models (ImmichAsset)
├── services/         # API service layer (ImmichApiService)
├── screens/          # UI screens (HomeScreen, SettingsScreen, PhotoDetailScreen)
├── widgets/          # Reusable UI components (PhotoGridItem)
└── main.dart         # App entry point

macos/                # macOS-specific files
├── Runner/           # macOS app configuration
├── Flutter/          # Flutter-macOS integration
└── Runner.xcodeproj/ # Xcode project files
```

## Building for Distribution

### macOS App Bundle:
```bash
flutter build macos
```
The built app will be in `build/macos/Build/Products/Release/`

### iOS App:
```bash
flutter build ios
```

### Android APK:
```bash
flutter build apk
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on multiple platforms
5. Submit a pull request

## License

This project is open source and available under the MIT License.

## Support

If you encounter any issues:
1. Check that your Immich server is accessible
2. Verify your API key is correct and has proper permissions
3. Ensure your server URL includes the protocol (https:// or http://)
4. Test the connection using the built-in connection test feature

### macOS-Specific Issues:
- If network requests fail, ensure the app has network permissions in macOS settings
- For development, make sure you have Xcode installed for building macOS apps

## Future Enhancements

- [ ] Search functionality
- [ ] Album browsing
- [ ] Photo upload capability
- [ ] Video playback
- [ ] Sharing functionality
- [ ] Offline photo caching
- [ ] Dark/Light theme toggle
- [ ] Windows and Linux desktop support
- [ ] Keyboard shortcuts for navigation # amimodo-immich-client
