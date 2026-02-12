import Foundation

// Diagnostic test to see which compilation conditions are active

#if USE_FOUNDATION_MODELS
let foundationModelsFlag = true
print("✅ USE_FOUNDATION_MODELS is defined")
#else
let foundationModelsFlag = false
print("❌ USE_FOUNDATION_MODELS is NOT defined")
#endif

#if canImport(FoundationModels)
let foundationModelsAvailable = true
print("✅ FoundationModels framework can be imported")
#else
let foundationModelsAvailable = false
print("❌ FoundationModels framework CANNOT be imported")
#endif

#if canImport(FoundationModelsMacros)
let foundationModelsMacrosAvailable = true
print("✅ FoundationModelsMacros framework can be imported")
#else
let foundationModelsMacrosAvailable = false
print("❌ FoundationModelsMacros framework CANNOT be imported")
#endif

// This will print at app launch
public struct FoundationModelsCheck {
    public static func diagnose() {
        print("""
        
        🔍 Foundation Models Diagnostic:
        ================================
        USE_FOUNDATION_MODELS flag: \(foundationModelsFlag ? "✅ YES" : "❌ NO")
        FoundationModels import: \(foundationModelsAvailable ? "✅ YES" : "❌ NO")
        FoundationModelsMacros import: \(foundationModelsMacrosAvailable ? "✅ YES" : "❌ NO")
        
        Combined result: \(foundationModelsFlag && foundationModelsAvailable && foundationModelsMacrosAvailable ? "✅ ENABLED" : "❌ DISABLED")
        ================================
        
        """)
    }
}
