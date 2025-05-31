import '../models/immich_asset.dart';

class PhotoDateUtils {
  /// Groups assets by year and month
  static Map<String, List<ImmichAsset>> groupAssetsByMonth(
      List<ImmichAsset> assets) {
    final Map<String, List<ImmichAsset>> grouped = {};

    for (final asset in assets) {
      final key = _getMonthKey(asset.createdAt);
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(asset);
    }

    return grouped;
  }

  /// Creates a sortable key for year/month grouping
  static String _getMonthKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  /// Formats the month key for display
  static String formatMonthHeader(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return monthKey;

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);

    if (year == null || month == null) return monthKey;

    final monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];

    final monthName =
        month > 0 && month <= 12 ? monthNames[month - 1] : 'Unknown';
    return '$monthName $year';
  }

  /// Gets sorted month keys (newest first)
  static List<String> getSortedMonthKeys(
      Map<String, List<ImmichAsset>> groupedAssets) {
    final keys = groupedAssets.keys.toList();
    keys.sort((a, b) => b.compareTo(a)); // Descending order (newest first)
    return keys;
  }

  /// Creates a data structure for rendering grouped assets in a grid
  static List<GroupedGridItem> createGroupedGridItems(
      Map<String, List<ImmichAsset>> groupedAssets) {
    final List<GroupedGridItem> items = [];
    final sortedKeys = getSortedMonthKeys(groupedAssets);

    for (final monthKey in sortedKeys) {
      final assets = groupedAssets[monthKey]!;

      // Add month header
      items.add(GroupedGridItem.header(
        monthKey: monthKey,
        displayText: formatMonthHeader(monthKey),
        assetCount: assets.length,
      ));

      // Add assets for this month
      for (int i = 0; i < assets.length; i++) {
        items.add(GroupedGridItem.asset(
          asset: assets[i],
          monthKey: monthKey,
          indexInMonth: i,
          globalAssetList: groupedAssets.values.expand((list) => list).toList(),
          globalIndex: _getGlobalIndex(groupedAssets, monthKey, i, sortedKeys),
        ));
      }
    }

    return items;
  }

  /// Gets the global index of an asset across all groups
  static int _getGlobalIndex(Map<String, List<ImmichAsset>> groupedAssets,
      String currentMonthKey, int indexInMonth, List<String> sortedKeys) {
    int globalIndex = 0;

    for (final monthKey in sortedKeys) {
      if (monthKey == currentMonthKey) {
        return globalIndex + indexInMonth;
      }
      globalIndex += groupedAssets[monthKey]!.length;
    }

    return globalIndex;
  }
}

/// Represents an item in a grouped grid (either a header or an asset)
class GroupedGridItem {
  final GroupedGridItemType type;
  final String? monthKey;
  final String? displayText;
  final int? assetCount;
  final ImmichAsset? asset;
  final int? indexInMonth;
  final List<ImmichAsset>? globalAssetList;
  final int? globalIndex;

  const GroupedGridItem._({
    required this.type,
    this.monthKey,
    this.displayText,
    this.assetCount,
    this.asset,
    this.indexInMonth,
    this.globalAssetList,
    this.globalIndex,
  });

  factory GroupedGridItem.header({
    required String monthKey,
    required String displayText,
    required int assetCount,
  }) {
    return GroupedGridItem._(
      type: GroupedGridItemType.header,
      monthKey: monthKey,
      displayText: displayText,
      assetCount: assetCount,
    );
  }

  factory GroupedGridItem.asset({
    required ImmichAsset asset,
    required String monthKey,
    required int indexInMonth,
    required List<ImmichAsset> globalAssetList,
    required int globalIndex,
  }) {
    return GroupedGridItem._(
      type: GroupedGridItemType.asset,
      asset: asset,
      monthKey: monthKey,
      indexInMonth: indexInMonth,
      globalAssetList: globalAssetList,
      globalIndex: globalIndex,
    );
  }
}

enum GroupedGridItemType { header, asset }
