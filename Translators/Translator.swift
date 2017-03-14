//
//  Translator.swift
//  SwresTools
//

import Foundation

enum TranslatorError: NestingSwresError {
    case unsupportedResource(reason: String)
    case invalidResource(reason: String?, underlyingError: Error?)

    var description: String {
        switch self {
        case .unsupportedResource(let reason):
            return "The resource may be valid but this translator is not able to convert it. \(reason)"
        case .invalidResource(let reason, _):
            var message = "The resource does not appear to be valid."
            if let unwrappedReason = reason {
                message += " \(unwrappedReason)"
            }
            return message
        }
    }

    var underlyingError: Error? {
        switch self {
        case .invalidResource(_, let error):
            return error
        default:
            return nil
        }
    }
}

enum TranslatorCompatibility {
    case notCompatible
    case possiblyCompatible
    case likelyCompatible
}

struct Translation {
    let data: Data
    let suggestedFileExtension: String
}

protocol Translator {
    func compatibilityWith(resource: Resource) -> TranslatorCompatibility
    func translate(resource: Resource) throws -> Translation
}
