# Apple Intelligence and Writing Tools Logging

## Date: February 11, 2026

## Overview

Added comprehensive logging to track all Apple Intelligence and Writing Tools interactions in the Console Log window.

## Changes Made

### 1. AppleFM Health Check Logging (`AppleFMHelper.swift`)

**Logs when:**
- Health check is attempted but `isEnabled=false`
- SystemLanguageModel availability is checked
- Session is created
- Ping/pong test completes
- OS version is too old

**Example output:**
```
[HH:mm:ss] [DEBUG] [AI] AppleFM health check: creating session
[HH:mm:ss] [DEBUG] [AI] AppleFM health check: pong received
```

### 2. AppleFM Completion Logging (`AppleFMHelper.swift`)

**Logs when:**
- Completion is requested (shows prompt length)
- Model availability is checked
- Response is received (shows response length and duration)
- Errors occur

**Example output:**
```
[HH:mm:ss] [INFO] [AI] AppleFM completion requested, prompt length: 245 chars
[HH:mm:ss] [INFO] [AI] AppleFM completion received: 187 chars in 1.23s
```

### 3. AppleFM Streaming Logging (`AppleFMHelper.swift`)

**Logs when:**
- Streaming starts (shows prompt length)
- Each chunk arrives (shows chunk number and size)
- Streaming completes (shows total chunks, chars, duration)
- Streaming fails and fallback is attempted
- Fallback succeeds or fails

**Example output:**
```
[HH:mm:ss] [INFO] [AI] AppleFM streaming started, prompt length: 512 chars
[HH:mm:ss] [DEBUG] [AI] AppleFM stream chunk #1: 15 chars
[HH:mm:ss] [DEBUG] [AI] AppleFM stream chunk #2: 23 chars
[HH:mm:ss] [DEBUG] [AI] AppleFM stream chunk #3: 18 chars
[HH:mm:ss] [INFO] [AI] AppleFM streaming completed: 3 chunks, 56 total chars in 0.85s
```

### 4. Text Change Logging (`EditorTextView.swift`)

**Logs when:**
- Text content changes (any edit, paste, or Writing Tools action)
- Shows text length and selection range
- Text is sanitized

**Example output:**
```
[HH:mm:ss] [DEBUG] [Editor] Text changed: length=1234, range={45, 0}
[HH:mm:ss] [DEBUG] [Editor] Text sanitized: 1234 → 1230 chars
```

## How to Use

### 1. Open Console Log
- Menu: **Diag → Show Console Log** (Cmd+Shift+L)
- The window shows all real-time logging

### 2. Filter for Specific Activity

**AI Operations Only:**
- In the Console Log search box, type: "AI"
- Or use the category filter

**Editor Changes Only:**
- Type: "Editor"
- Or filter by DEBUG level

**Apple Intelligence Streaming:**
- Type: "stream chunk"
- Shows each piece of text as it arrives

### 3. Detect Writing Tools Usage

When you use **Edit → Writing Tools → Make Professional**:

1. Select some text
2. Open Console Log (Cmd+Shift+L)
3. Apply Writing Tools
4. Watch for:
   - Multiple "Text changed" entries (as AI edits)
   - Possibly AppleFM completion logs (if it uses Foundation Models)
   - Changes in text length

**Expected log pattern:**
```
[HH:mm:ss] [DEBUG] [Editor] Text changed: length=500, range={100, 50}
[HH:mm:ss] [DEBUG] [Editor] Text changed: length=520, range={150, 0}
[HH:mm:ss] [DEBUG] [Editor] Text changed: length=525, range={155, 0}
```

## Writing Tools Detection

### What Writing Tools Are

Writing Tools are system-level AI features in macOS 26.0+ that provide:
- **Proofread**: Fix grammar and spelling
- **Rewrite**: Rephrase text
- **Make Professional**: Convert to professional tone
- **Make Friendly**: Convert to friendly tone
- **Make Concise**: Shorten text
- **Summarize**: Create summary
- **Extract Key Points**: List main points
- **Create Table**: Format as table
- **Create List**: Format as list

### How They Appear in Logs

Writing Tools operate **directly on NSTextView** and trigger:
1. ✅ `textDidChange` notifications (we log these)
2. ✅ Text selection changes (logged with range)
3. ⚠️ May or may not use your app's AppleFM methods (depends on system implementation)

**Note**: Writing Tools are system-level and may use Apple Intelligence **directly** without going through your app's AppleFM helper. The text change logs will still show the edits happening.

## Comprehensive Logging Coverage

### Logged Operations

✅ **Apple Intelligence API calls:**
- Health checks
- Completions (non-streaming)
- Streaming (with per-chunk detail)
- Errors and fallbacks

✅ **Text Edits:**
- Every change to editor content
- Selection position
- Sanitization operations

✅ **AI Suggestions (from Tools menu):**
- Request initiated
- Provider selected
- Completion time and size

✅ **File Operations:**
- File opened/saved (from EditorViewModel)
- Success and error cases

### Not Directly Logged

⚠️ **System Writing Tools internal operations:**
- Writing Tools make their own API calls to Apple servers
- They edit the text view directly
- We only see the **results** (text changes)

⚠️ **Apple Intelligence system prompts:**
- The exact prompts Writing Tools send
- System-level model selection
- Processing details

## Debugging Scenarios

### Scenario 1: Testing Writing Tools

1. Open Console Log (Cmd+Shift+L)
2. Clear logs (trash button)
3. Select text in editor
4. Use Edit → Writing Tools → Make Professional
5. Observe logs:
   - Should see multiple "Text changed" entries
   - Check if text length changes
   - Note the timing

### Scenario 2: Testing Your App's AI Features

1. Open Console Log
2. Clear logs
3. Use Tools → Suggest Code (Cmd+Shift+G)
4. Observe logs:
   ```
   [INFO] [AI] Suggest Code requested for swift file
   [INFO] [AI] Using Apple Intelligence
   [INFO] [AI] AppleFM streaming started, prompt length: XXX chars
   [DEBUG] [AI] AppleFM stream chunk #1: XX chars
   ...
   [INFO] [AI] AppleFM streaming completed: ...
   [INFO] [AI] AI suggestion completed in X.XXs, XXX characters
   ```

### Scenario 3: Comparing Providers

1. Open Console Log
2. Filter by category: "AI"
3. Try "Suggest Code" with different providers:
   - Apple Intelligence: See AppleFM logs
   - Anthropic: See "Using Anthropic Claude" and timing
   - OpenAI/Gemini/Grok: See provider name and timing

## Log Levels Explained

| Level | Usage | Example |
|-------|-------|---------|
| **DEBUG** | Detailed operations, chunked data | "AppleFM stream chunk #5: 12 chars" |
| **INFO** | Normal operations, results | "AppleFM completion received: 187 chars in 1.23s" |
| **WARNING** | Non-critical issues | "AppleFM stream attempted but isEnabled=false" |
| **ERROR** | Failures, exceptions | "SystemLanguageModel unavailable" |

## Export Logs

To save logs for debugging:

1. Use the export button (↑) in Console Log toolbar
2. Choose filename (includes timestamp)
3. Logs saved as plain text with all metadata
4. Share for troubleshooting or analysis

## Performance Impact

- **DEBUG logs**: Only in Debug builds, minimal impact
- **INFO logs**: Always on, very light (just string formatting)
- **WARNING/ERROR logs**: Only when issues occur
- **No impact on AI performance**: Logging happens after/during operations

## Future Enhancements

Potential additions:
- Log the actual prompt text (truncated)
- Log Writing Tools API calls if we can intercept them
- Chart view of AI response times
- Statistics on model usage
- Export logs in JSON format

---

**Author**: Claude (Anthropic)  
**Status**: ✅ Complete  
**Build and run**: Clean build required to see new logs
