//
//  PascalStringTranslator.swift
//  SwresTools
//

import Foundation

struct PascalStringTranslator: Translator {
    @discardableResult func _looksLikePascalString(_ data: Data) throws -> Bool {
        guard data.count > 0 else {
            throw TranslatorError.unsupportedResource(reason: "Can't translate empty data.")
        }

        let length = data[0]
        guard data.count == Int(length) + 1 else {
            throw TranslatorError.unsupportedResource(reason: "Resource length doesn't match first byte prefix.")
        }

        return true
    }

    static private var _strType: FourCharCode = try! FourCharCode("STR ")

    func compatibilityWith(resource: Resource) -> TranslatorCompatibility {
        do {
            try _looksLikePascalString(resource.data)
        } catch {
            return TranslatorCompatibility.notCompatible
        }

        switch resource.type {
        case PascalStringTranslator._strType:
            return TranslatorCompatibility.likelyCompatible
        default:
            return TranslatorCompatibility.possiblyCompatible
        }
    }

    func translate(resource: Resource) throws -> Translation {
        let data = resource.data
        try _looksLikePascalString(data)

        let options = MacOSRomanConversionOptions(filterControlCharacters: false, filterFilesystemUnsafeCharacters: false, filterNonASCIICharacters: false, replacementMacOSRomanByte: nil)
        let string = stringFromMacOSRomanBytes(data.subdata(in: 1..<data.count), options: options)
        let stringData = string.data(using: String.Encoding.utf8)

        return Translation(data: stringData!, suggestedFileExtension: "txt")
    }
}
