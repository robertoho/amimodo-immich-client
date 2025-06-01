import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../screens/photo_detail_screen.dart';
import 'optimized_cached_thumbnail_image.dart';

class PhotoGridItem extends StatefulWidget {
  ImmichAsset asset;
  ImmichApiService apiService;
  bool isSelectionMode;
  bool isSelected;
  VoidCallback? onSelectionToggle;
  List<ImmichAsset>? assetList;
  int? assetIndex;

  PhotoGridItem({
    super.key,
    required this.asset,
    required this.apiService,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionToggle,
    this.assetList,
    this.assetIndex,
  });

  void setSelected(bool selected) {
    // This method will be called by the state when the widget is created
    // We'll store a reference to the state and call its method
    final state = (key as GlobalKey?)?.currentState as _PhotoGridItemState?;
    state?.setSelected(selected);
  }

  @override
  State<PhotoGridItem> createState() => _PhotoGridItemState();
}

class _PhotoGridItemState extends State<PhotoGridItem> {
  void setSelected(bool selected) {
    setState(() {
      widget.isSelected = selected;
      widget.onSelectionToggle?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (widget.isSelectionMode) {
          widget.onSelectionToggle?.call();
          setState(() {
            widget.isSelected = !widget.isSelected;
          });
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PhotoDetailScreen(
                assets: widget.assetList ?? [widget.asset],
                initialIndex: widget.assetIndex ?? 0,
                apiService: widget.apiService,
              ),
            ),
          );
        }
      },
      onLongPress: () {
        if (!widget.isSelectionMode) {
          _showExifOverlay(context);
        }
      },
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: AspectRatio(
            aspectRatio: 1.0, // Square aspect ratio
            child: Stack(
              fit: StackFit.expand,
              children: [
                OptimizedCachedThumbnailImage(
                  assetId: widget.asset.id,
                  apiService: widget.apiService,
                ),
                // Selection overlay
                if (widget.isSelectionMode)
                  Container(
                    color: widget.isSelected
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                        : Colors.black.withOpacity(0.1),
                  ),
                // Video indicator
                if (widget.asset.type.toUpperCase() == 'VIDEO')
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                // Favorite indicator
                if (widget.asset.isFavorite)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.red,
                        size: 16,
                      ),
                    ),
                  ),
                // Selection indicator
                if (widget.isSelectionMode)
                  Positioned(
                    top: 8,
                    right: widget.isSelected
                        ? 8
                        : (widget.asset.type.toUpperCase() == 'VIDEO' ? 32 : 8),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white.withOpacity(0.8),
                        border: Border.all(
                          color: widget.isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                          width: 2,
                        ),
                      ),
                      child: widget.isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showExifOverlay(BuildContext context) async {
    // Show loading dialog first
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Loading EXIF data...'),
          ],
        ),
      ),
    );

    try {
      // Fetch detailed asset info
      final assetInfo = await widget.apiService.getAssetInfo(widget.asset.id);

      // Close loading dialog
      Navigator.of(context).pop();

      // Show EXIF data overlay
      _showExifDataDialog(context, assetInfo);
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load EXIF data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showExifDataDialog(
      BuildContext context, Map<String, dynamic> assetInfo) {
    final exifInfo = assetInfo['exifInfo'] as Map<String, dynamic>?;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.white,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Photo Information',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoSection('Basic Info', [
                        _buildInfoRow('File Name',
                            _getFileName(widget.asset.originalPath)),
                        _buildInfoRow('Type', widget.asset.type),
                        _buildInfoRow(
                            'Created', _formatDateTime(widget.asset.createdAt)),
                        _buildInfoRow('Modified',
                            _formatDateTime(widget.asset.modifiedAt)),
                        _buildInfoRow(
                            'Favorite', widget.asset.isFavorite ? 'Yes' : 'No'),
                      ]),
                      if (exifInfo != null) ...[
                        SizedBox(height: 16),
                        _buildExifSection(context, exifInfo),
                      ],
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

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'N/A',
              style: TextStyle(
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExifSection(
      BuildContext context, Map<String, dynamic> exifInfo) {
    final exifItems = <Widget>[];

    // Check if GPS coordinates are available
    final gpsLat = exifInfo['gpsLatitude'];
    final gpsLng = exifInfo['gpsLongitude'];
    final hasGpsCoordinates = gpsLat != null &&
        gpsLng != null &&
        gpsLat.toString().isNotEmpty &&
        gpsLng.toString().isNotEmpty;

    // Add map if GPS coordinates are available
    if (hasGpsCoordinates) {
      try {
        final latitude = double.parse(gpsLat.toString());
        final longitude = double.parse(gpsLng.toString());

        exifItems.add(
          Container(
            height: 200,
            margin: EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(latitude, longitude),
                  initialZoom: 15.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.immich_flutter_app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(latitude, longitude),
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        exifItems.add(SizedBox(height: 8));
      } catch (e) {
        // If GPS coordinates can't be parsed, just show them as text
      }
    }

    // Common EXIF fields to display
    final commonFields = {
      'make': 'Camera Make',
      'model': 'Camera Model',
      'lensModel': 'Lens Model',
      'fNumber': 'Aperture',
      'exposureTime': 'Shutter Speed',
      'focalLength': 'Focal Length',
      'iso': 'ISO',
      'dateTime': 'Date Taken',
      'gpsLatitude': 'GPS Latitude',
      'gpsLongitude': 'GPS Longitude',
      'description': 'Description',
      'imageWidth': 'Width',
      'imageHeight': 'Height',
      'orientation': 'Orientation',
      'colorSpace': 'Color Space',
      'whiteBalance': 'White Balance',
      'flash': 'Flash',
      'meteringMode': 'Metering Mode',
      'exposureMode': 'Exposure Mode',
      'sceneCaptureType': 'Scene Mode',
    };

    for (final entry in commonFields.entries) {
      final value = exifInfo[entry.key];
      if (value != null && value.toString().isNotEmpty) {
        exifItems.add(
            _buildInfoRow(entry.value, _formatExifValue(entry.key, value)));
      }
    }

    if (exifItems.isEmpty) {
      exifItems.add(
        Text(
          'No EXIF data available',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return _buildInfoSection('EXIF Data', exifItems);
  }

  String _formatExifValue(String key, dynamic value) {
    switch (key) {
      case 'fNumber':
        return 'f/${value}';
      case 'exposureTime':
        return value.toString().contains('/')
            ? '${value}s'
            : '1/${(1 / double.parse(value.toString())).round()}s';
      case 'focalLength':
        return '${value}mm';
      case 'iso':
        return 'ISO ${value}';
      case 'imageWidth':
      case 'imageHeight':
        return '${value}px';
      case 'dateTime':
        final dateTime = DateTime.tryParse(value.toString());
        return dateTime != null ? _formatDateTime(dateTime) : value.toString();
      case 'gpsLatitude':
      case 'gpsLongitude':
        return '${value}°';
      default:
        return value.toString();
    }
  }

  String _getFileName(String path) {
    return path.split('/').last;
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
