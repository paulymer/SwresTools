//
//  TranslatorManager
//  SwresTools
//

import Foundation

enum TranslatorFilter: Int, Comparable {
    case noTranslators
    case onlyLikelyTranslators
    case likelyAndPossibleTranslators

    static func <(lhs: TranslatorFilter, rhs: TranslatorFilter) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

enum TranslationResult {
    case translated(_: Translation)
    case error(_: Error)
}

struct TranslatorManager {
    static let sharedInstance = TranslatorManager()

    private let _translators: Array<Translator>

    private init() {
        _translators = [
            PascalStringTranslator(),
            SndTranslator(),
        ]
    }

    func translate(_ resource: Resource, includeTranslators translatorFilter: TranslatorFilter = TranslatorFilter.noTranslators) -> Array<TranslationResult> {
        var translationResults = Array<TranslationResult>()

        let translatorsByCompatibility = _translators.groupBy({ (translator: Translator) in
            return translator.compatibilityWith(resource: resource)
        })

        var applicableTranslators = Array<Translator>()
        if let likelyTranslators = translatorsByCompatibility[TranslatorCompatibility.likelyCompatible] {
            applicableTranslators.append(contentsOf: likelyTranslators)
        }

        if translatorFilter >= TranslatorFilter.likelyAndPossibleTranslators, let possibleTranslators = translatorsByCompatibility[TranslatorCompatibility.possiblyCompatible] {
            applicableTranslators.append(contentsOf: possibleTranslators)
        }

        for translator in applicableTranslators {
            do {
                let translation = try translator.translate(resource: resource)
                translationResults.append(TranslationResult.translated(translation))
            } catch let error {
                translationResults.append(TranslationResult.error(error))
            }
        }

        return translationResults
    }
}
