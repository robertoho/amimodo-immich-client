# Improved Thumbnail Loading Strategy

## Overview

This implementation introduces an efficient thumbnail loading strategy that prioritizes local database storage and background pre-loading to improve user experience when scrolling through photos.

## Key Components

### 1. BackgroundThumbnailService (`lib/services/background_thumbnail_service.dart`)

A singleton service that manages background downloading of thumbnails:

- **Queue Management**: Maintains queues for pending downloads, currently downloading, and completed assets
- **Concurrency Control**: Limits concurrent downloads (default: 3) to prevent overwhelming the server
- **Batch Processing**: Downloads thumbnails in batches (default: 10) for efficiency
- **Priority System**: Allows prioritizing specific assets (e.g., currently visible ones)
- **Status Monitoring**: Provides real-time status updates via streams

### 2. OptimizedCachedThumbnailImage (`lib/widgets/optimized_cached_thumbnail_image.dart`)

An optimized image widget that follows this loading strategy:

1. **First**: Check local cache (Hive database) for existing thumbnail
2. **Second**: If not cached, request priority download from background service
3. **Third**: As fallback, download immediately if background service fails

### 3. Integration with MetadataSearchScreen

The search screen now:

- Starts background downloads immediately when new assets are loaded
- Prioritizes visible assets when scrolling
- Shows download progress in the status widget
- Provides controls to pause/resume background downloads

## Loading Strategy Flow

```
User searches for assets
         ↓
Assets loaded from server (metadata only)
         ↓
Background service starts downloading ALL thumbnails
         ↓
User scrolls through results
         ↓
Visible assets are prioritized for immediate download
         ↓
Image widgets check local cache first
         ↓
If cached: Display immediately
If not cached: Request priority download + fallback to immediate download
```

## Benefits

1. **Faster Scrolling**: Thumbnails are pre-loaded in the background
2. **Reduced Server Load**: Only query server for search, thumbnails are cached locally
3. **Better UX**: Immediate display of cached thumbnails, smooth scrolling
4. **Efficient Memory Usage**: Uses existing Hive-based caching system
5. **Prioritization**: Visible content loads first, background content loads later
6. **Resilient**: Multiple fallback strategies ensure images always load

## Configuration

Key constants in `BackgroundThumbnailService`:

- `_maxConcurrentDownloads`: Maximum simultaneous downloads (default: 3)
- `_batchSize`: Number of assets processed per batch (default: 10)
- `_downloadDelay`: Delay between batches (default: 100ms)

## Usage

The system works automatically once integrated. Key methods:

```dart
// Start background downloads for a list of assets
await backgroundService.startBackgroundDownload(assets, apiService);

// Prioritize specific assets (e.g., currently visible)
await backgroundService.prioritizeAssets(assetIds, apiService);

// Check if thumbnail is cached locally
bool isCached = await backgroundService.isAssetThumbnailCached(assetId, apiService);

// Get cached thumbnail data
Uint8List? thumbnail = await backgroundService.getCachedAssetThumbnail(assetId, apiService);
```

## Status Monitoring

The service provides real-time status updates:

```dart
StreamBuilder<BackgroundDownloadStatus>(
  stream: backgroundService.statusStream,
  builder: (context, snapshot) {
    final status = snapshot.data ?? backgroundService.currentStatus;
    // Display progress: status.completed / status.total
  },
);
```

## Performance Considerations

- **Memory Efficient**: Uses existing Hive cache with LRU cleanup
- **Network Efficient**: Batched downloads with concurrency limits
- **CPU Efficient**: Background processing doesn't block UI
- **Storage Efficient**: Leverages existing thumbnail cache system

This strategy ensures that users see thumbnails immediately when scrolling (if cached) while the system proactively downloads remaining thumbnails in the background. 