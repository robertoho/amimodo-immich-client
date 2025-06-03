# Test Guide: Bidirectional Thumbnail Preload Feature

## How to Test the Bidirectional Preload Feature

### 1. **Start the App**
```bash
flutter run
```

### 2. **Configure Account**
- Make sure you have an Immich account configured
- Go to Settings and verify your server connection

### 3. **Search for Assets**
- Open the Metadata Search screen
- Apply some search filters (optional, but recommended for testing)
- Verify some assets are found and displayed

### 4. **Navigate to a Specific Position**
- **Scroll to a middle position** in your asset list (e.g., asset 500 out of 1000)
- **Stop scrolling and wait 3 seconds** for the preload starting index to update
- **Check the status widget**: Look for "Preload Start: X" showing your current position
- Note your current position for testing

### 5. **Test Dynamic Starting Position Updates**
- **Scroll to different positions** and wait 3 seconds each time
- **Watch the status widget**: "Preload Start" should update to reflect your new position
- **Console Output**: Look for "🎯 Updated preload starting index to X"
- **Verify**: The preload start position follows your scroll position with a delay

### 6. **Start Bidirectional Preload**
- Look for the cloud sync icon (📥) in the app bar
- Tap the cloud sync icon
- Review the confirmation dialog showing:
  - **Starting position**: "Starting from position X of Y visible assets"
  - Current search filters
- Tap "Start Preload" to begin

### 7. **Monitor Bidirectional Progress**
- Watch the status widget show:
  - "Starting bidirectional preload from current position..."
  - "Expanding outward from start position - Page X"
  - **Notice the page numbers jumping around** as it alternates between forward/backward directions
  - Progress indicators showing downloads from both directions

### 8. **Verify Bidirectional Behavior**
- **Check Console Output** for bidirectional processing:
  ```
  📍 Starting from page 25 (based on asset index 500)
  🔍 Processing page 25... (starting page)
  🔍 Processing page 26... (forward)
  🔍 Processing page 24... (backward)
  🔍 Processing page 27... (forward)
  🔍 Processing page 23... (backward)
  ```
- **Immediate Results**: Thumbnails around your current position load first
- **Expanding Coverage**: Downloads spread outward in both directions

### 9. **Test Cache Behavior**
- Run preload once, let it complete
- Start preload again from different position
- Notice cached assets are skipped regardless of direction
- Pages with all cached assets process instantly

### 10. **Test Different Starting Positions**
- Try starting from the **beginning** of the list (position 1)
- Try starting from the **end** of the list (last position)
- Try starting from various **middle positions**
- Verify it always expands outward appropriately

### 11. **Test Controls**
- Try pausing/resuming during bidirectional preload
- Try stopping the preload by tapping the cloud download icon again
- Restart from different positions

### 12. **Test Scroll-Stop Position Updates**
- **Active Scrolling**: While scrolling, the "Preload Start" position doesn't change
- **Stop and Wait**: Stop scrolling for 3+ seconds, watch position update
- **Threshold Test**: Small movements (< 50 assets) won't trigger updates
- **Large Movements**: Move 50+ assets and wait, should see position update
- **Console Verification**: Look for "🎯 Updated preload starting index to X"

## Expected Behavior

### **Dynamic Starting Position** 🎯
- **Initial Position**: Preload starts from position 1 when app first loads
- **Scroll Tracking**: As you scroll, system tracks your current position
- **Update on Stop**: After scrolling stops for 3 seconds, preload starting position updates
- **Smart Threshold**: Only updates if you've moved 50+ assets (prevents micro-adjustments)
- **Status Display**: "Preload Start: X" in status widget shows current starting position
- **Persistent**: Starting position remembers your last stopped position

### **Bidirectional Expansion Strategy** ✨
- **Smart Starting Point**: Begins from your current scroll position
- **Outward Expansion**: Downloads forward (1001, 1002, 1003...) and backward (999, 998, 997...)
- **Alternating Direction**: Switches between forward/backward pages for balanced coverage
- **Priority to Nearby**: Assets closest to your position download first
- **Complete Coverage**: Eventually covers all matching assets

### **Immediate User Benefits**
- **Faster Visible Results**: See thumbnails loading around your current position immediately
- **Better User Experience**: No waiting for distant assets to load first
- **Intelligent Prioritization**: Most relevant assets (nearby) load first
- **Responsive Navigation**: Smooth scrolling as nearby assets are already cached

### **Page Processing Pattern**
```
Starting from position 1000 (page 5):
Page 5 (current) → Page 6 (forward) → Page 4 (backward) → 
Page 7 (forward) → Page 3 (backward) → Page 8 (forward) → 
Page 2 (backward) → Page 9 (forward) → Page 1 (backward) → ...
```

### **Cache-Aware Bidirectional Processing**
- **Efficient**: Only downloads uncached thumbnails in both directions
- **Smart**: Skips cached assets regardless of direction
- **Persistent**: Cache survives app restarts
- **Consistent**: Same cache behavior as before, just smarter ordering

### **Completion Status**
- Status shows "Bidirectional preload completed: X downloaded, Y were already cached"
- All thumbnails for matching assets are cached locally
- **Subsequent navigation is instant** in both directions
- **Optimal for user workflow**: Near-current assets load first

## Debug Output (Bidirectional Processing)

Watch the console for the new bidirectional debug messages:
```
🎯 Updated preload starting index to 1250 (visible: 50, removed: 1200)
🎯 Starting preload from global index 1250 (visible: 50, removed: 1200)
🚀 Starting full thumbnail preload from position 1250 - expanding outward...
📍 Starting from page 7 (based on asset index 1250)
🔍 Processing page 7...
📄 Page 7: 200 assets, 150 cached, 50 queued for download
🔍 Processing page 8... (forward)
📄 Page 8: 200 assets, 180 cached, 20 queued for download
🔍 Processing page 6... (backward)
📄 Page 6: 200 assets, 160 cached, 40 queued for download
🔍 Processing page 9... (forward)
🔍 Processing page 5... (backward)
📊 Processing complete: 2000 total assets, 1800 already cached, 200 downloaded
✅ Full thumbnail preload completed - now have 2000 thumbnails in cache
```

## Scroll-Stop Debug Messages

New console output for dynamic starting position updates:
```
🎯 Updated preload starting index to 750 (visible: 125, removed: 625)
🎯 Updated preload starting index to 1200 (visible: 50, removed: 1150)  
🎯 Updated preload starting index to 300 (visible: 300, removed: 0)
```

## Bidirectional Advantages

### **User Experience Improvements**
- ✅ **Immediate gratification**: See results around current position first
- ✅ **Natural workflow**: Prioritizes assets user is likely to view next
- ✅ **Balanced coverage**: Expands in both directions simultaneously
- ✅ **Responsive interface**: Smooth scrolling as nearby assets are cached
- ✅ **Dynamic positioning**: Starting position automatically updates as you scroll
- ✅ **Smart updates**: Only updates position after scrolling stops (3 second delay)

### **Technical Optimizations**
- ✅ **Smart page ordering**: Alternates between forward/backward for even coverage
- ✅ **Position-aware**: Calculates global index accounting for memory management
- ✅ **Cache-efficient**: Still skips cached thumbnails in both directions
- ✅ **Memory-safe**: Handles edge cases (beginning/end of list)
- ✅ **Scroll optimization**: Timer prevents constant position recalculation
- ✅ **Threshold filtering**: Ignores small movements (< 50 assets) to prevent noise

### **Practical Benefits**
- ✅ **Photo browsing**: Perfect for reviewing photos around current position
- ✅ **Search results**: Ideal for exploring search results from current focus
- ✅ **Large libraries**: Handles massive asset collections efficiently
- ✅ **Network optimization**: Downloads most relevant content first

## Performance Notes

- **Network Usage**: Prioritizes nearby assets, reducing perceived loading time
- **Processing**: **Bidirectional expansion** - intelligent page ordering
- **Memory**: Same efficiency as before, just smarter download sequence
- **User Experience**: **Dramatically improved** - immediate results around current position
- **Server Load**: Minimal - same page-by-page processing, just different order
- **Cache-Aware**: **Never re-downloads existing thumbnails** in either direction

## Troubleshooting

### **Position Calculation Issues**
- **Problem**: Starting from wrong position
- **Check**: Console shows "Starting preload from global index X"
- **Verify**: Position accounts for memory management (_assetsRemovedFromStart)

### **Bidirectional Verification**
- **Check Console**: Should show alternating page numbers (forward/backward)
- **Page Pattern**: Should see pages like 5→6→4→7→3→8→2...
- **Starting Page**: Should calculate correctly from asset index

### **Edge Cases**
- **Start from beginning**: Should only expand forward
- **Start from end**: Should only expand backward  
- **Single page**: Should process normally without alternation

### **Cache Efficiency**
- **Same as before**: Skips cached assets in both directions
- **Persistent**: Cache survives app restarts
- **Consistent**: No change in cache behavior, just download order

## Testing Scenarios

### **Scenario 1: Middle Position Start**
```
Assets: 1000 total, currently viewing position 500
Expected: Start page 3, then 4→2→5→1→6→7...
Result: Thumbnails around position 500 appear first
```

### **Scenario 2: Beginning Position Start**
```
Assets: 1000 total, currently viewing position 1
Expected: Start page 1, then 2→3→4→5...
Result: Downloads proceed forward only (no backward)
```

### **Scenario 3: End Position Start**
```
Assets: 1000 total, currently viewing position 1000
Expected: Start page 5, then 4→3→2→1...
Result: Downloads proceed backward only (no forward)
```

### **Scenario 4: With Memory Management**
```
Assets: 5000 total, 800 removed from start, viewing position 200 in memory
Global position: 1000 (800 + 200)
Expected: Start from page 5, expand bidirectionally
Result: Correct global position calculation
``` 