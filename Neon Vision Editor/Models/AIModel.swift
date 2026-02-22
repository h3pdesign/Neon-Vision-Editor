//  AIModel.swift
//  Neon Vision Editor
//  Created by Hilthart Pedersen on 06.02.26.


import Foundation
// Supported AI providers for suggestions. Extend as needed.
public enum AIModel: String, CaseIterable, Identifiable {
    case appleIntelligence
    case grok
    case openAI
    case gemini
    case anthropic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple"
        case .grok: return "Grok"
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .anthropic: return "Anthropic"
        }
    }
}
