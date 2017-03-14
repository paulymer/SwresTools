//
//  Resource.swift
//  SwresTools
//

import Foundation

struct Resource: CustomStringConvertible {
    let type: FourCharCode
    let identifier: Int16
    let name: Data?
    let data: Data

    var stringName: String? {
        guard let name = name else {
            return nil
        }

        let options = MacOSRomanConversionOptions(filterControlCharacters: true, filterFilesystemUnsafeCharacters: false, filterNonASCIICharacters: false, replacementMacOSRomanByte: MacOSRomanByteQuestionMark)
        return stringFromMacOSRomanBytes(name, options: options)
    }

    var description: String {
        let formattedName = stringName ?? ""
        return "<Resource type: \"\(type)\", identifier: \(identifier), name: \"\(formattedName)\", data length: \(data.count)>"
    }
}
