# Apple Intelligence Error Fix

## Issue

The console log was showing "Apple Intelligence: Error" even though Apple Intelligence was enabled in macOS Settings.

## Root Cause

The `AppleFM` helper class has a **safety flag** called `isEnabled` that defaults to `false`. This was intentionally designed to prevent accidental usage of Foundation Models without explicit opt-in.

From `AppleFMHelper.swift`:
```swift
public enum AppleFM {
    /// Global toggle to enable Apple Foundation Models features at runtime.
    /// Defaults to `false` so code completion/AI features are disabled by default.
    public static var isEnabled: Bool = false
```

When `isEnabled` is `false`, the health check throws this error:
```
"Foundation Models feature is disabled by default. Enable via AppleFM.isEnabled = true."
```

## Solution

Added `AppleFM.isEnabled = true` at app startup, **before** the health check runs.

### Changes Made

#### 1. App Startup (`NeonVisionEditorApp.swift`)

**Before:**
```swift
.task {
    #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
    do {
        let start = Date()
        _ = try await AppleFM.appleFMHealthCheck()
        // ...
    }
    #endif
}
```

**After:**
```swift
.task {
    #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
    AppleFM.isEnabled = true  // ← Added this line
    AppLogger.shared.info("Checking Apple Intelligence availability...", category: "AI")
    do {
        let start = Date()
        _ = try await AppleFM.appleFMHealthCheck()
        // ...
        AppLogger.shared.info("Apple Intelligence ready (RTT: X.Xms)", category: "AI")
    } catch {
        AppLogger.shared.error("Apple Intelligence error: \(error.localizedDescription)", category: "AI")
    }
    #endif
}
```

#### 2. Manual Health Check Button (`NeonVisionEditorApp.swift`)

Also added to the "Run AI Check" diagnostic button:

```swift
Button("Run AI Check") {
    Task {
        AppLogger.shared.info("Running Apple Intelligence health check...", category: "AI")
        #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
        AppleFM.isEnabled = true  // ← Added this line
        do {
            _ = try await AppleFM.appleFMHealthCheck()
            AppLogger.shared.info("Apple Intelligence health check passed...", category: "AI")
        }
        #endif
    }
}
```

#### 3. Auto-Completion Toggle (Already Present)

The code already enabled it when auto-completion is toggled on (in `ContentView.swift`):

```swift
func toggleAutoCompletion() {
    let willEnable = !isAutoCompletionEnabled
    isAutoCompletionEnabled.toggle()
    if willEnable {
        #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
        AppleFM.isEnabled = true  // ← Already present
        #endif
    }
}
```

## Why This Design?

The `AppleFM.isEnabled` flag exists for several good reasons:

1. **Privacy & Performance**: Foundation Models run on-device but still consume resources
2. **Explicit Opt-In**: Ensures developers/users consciously enable AI features
3. **Feature Flag**: Easy to disable AI features during development or testing
4. **Graceful Degradation**: App continues working if Foundation Models unavailable

## Expected Behavior After Fix

### On macOS 15+ with Apple Intelligence Enabled

**Console Log:**
```
[HH:mm:ss.SSS] [INFO] [App] Neon Vision Editor launched
[HH:mm:ss.SSS] [INFO] [AI] Checking Apple Intelligence availability...
[HH:mm:ss.SSS] [INFO] [AI] Apple Intelligence ready (RTT: 150.2ms)
```

**Diag Menu:**
- Shows "AI: Ready" status
- RTT (Round Trip Time) displayed in milliseconds

### On macOS 14 or Earlier

**Console Log:**
```
[HH:mm:ss.SSS] [INFO] [App] Neon Vision Editor launched
[HH:mm:ss.SSS] [ERROR] [AI] Apple Intelligence error: Apple Intelligence requires iOS 18 / macOS 15 or later.
```

**Diag Menu:**
- Shows "AI: Error" status
- App still works, but falls back to external providers

### Without Foundation Models Enabled in Build

**Console Log:**
```
[HH:mm:ss.SSS] [INFO] [App] Neon Vision Editor launched
[HH:mm:ss.SSS] [WARNING] [AI] Apple Intelligence not available in this build
```

**Diag Menu:**
- Shows "AI: Unavailable" status

## Troubleshooting

If you still see Apple Intelligence errors after this fix:

### 1. Check macOS Version
```swift
// Requires macOS 15.0 or later
if #available(macOS 15.0, *) {
    // Foundation Models available
}
```

### 2. Check Apple Intelligence System Settings
- Open **System Settings** → **Apple Intelligence & Siri**
- Ensure Apple Intelligence is **ON**
- May require signing in with Apple Account

### 3. Check Build Configuration
Ensure your Xcode project has:
- `USE_FOUNDATION_MODELS` preprocessor flag defined
- Proper entitlements for Foundation Models
- Swift version 6.0+

### 4. Check Model Availability
The code checks `SystemLanguageModel.default.availability`:
- `.available` - Model is ready
- `.unavailable` - Model not ready (system issue)
- `.denied` - User denied permission (rare)

### 5. Verify Logging
Check the console log window for detailed error messages:
- Open Console Log: **Diag** → **Show Console Log** (Cmd+Shift+L)
- Filter by category: "AI"
- Look for ERROR level messages

## Testing

### Manual Test Steps

1. **Launch the app**
   - Console log should show "Checking Apple Intelligence availability..."
   - Should resolve to either "ready" or specific error

2. **Open Console Log** (Cmd+Shift+L)
   - Filter by "AI" category
   - Verify no "disabled by default" errors

3. **Run Manual Health Check**
   - Menu: **Diag** → **Run AI Check**
   - Console should log the attempt and result
   - Diag menu should update status

4. **Test "Suggest Code"** (Cmd+Shift+G)
   - Open a Swift file
   - Trigger "Suggest Code"
   - Console should show provider selection and completion time

### Expected Console Output

#### Successful Startup
```
[12:00:00.000] [INFO] [App] Neon Vision Editor launched
[12:00:00.100] [INFO] [AI] Checking Apple Intelligence availability...
[12:00:00.250] [INFO] [AI] Apple Intelligence ready (RTT: 150.0ms)
```

#### Using Suggest Code
```
[12:01:00.000] [INFO] [AI] Suggest Code requested for swift file
[12:01:00.010] [INFO] [AI] Using Apple Intelligence
[12:01:02.500] [INFO] [AI] AI suggestion completed in 2.49s, 287 characters
```

## Related Files

- `AppleFMHelper.swift` - Foundation Models wrapper with `isEnabled` flag
- `NeonVisionEditorApp.swift` - App initialization and health checks
- `ContentView.swift` - Auto-completion toggle
- `AIClient.swift` - `AppleIntelligenceAIClient` implementation

## References

- Apple Documentation: [FoundationModels Framework](https://developer.apple.com/documentation/foundationmodels)
- Requires: macOS 15.0+, iOS 18.0+
- System Requirements: Apple Silicon Mac or A17 Pro/A18 iPhone/iPad

---

**Fixed**: February 11, 2026  
**Author**: Claude (Anthropic)  
**Status**: ✅ Resolved
