//
//  FourCharCode.swift
//  SwresTools
//

import Foundation

enum FourCharCodeError: SwresError {
    case invalidSequence

    var description: String {
        return "Cannot construct FourCharCode from invalid byte sequence."
    }
}

struct FourCharCode: Equatable, Hashable, CustomStringConvertible {
    let bytes: Data

    init(_ bytes: Data) throws {
        guard bytes.count == 4 else {
            throw FourCharCodeError.invalidSequence
        }
        self.bytes = bytes
    }

    init(_ cString: UnsafeMutablePointer<CChar>) throws {
        let string = String(cString: cString)
        try self.init(string)
    }

    init(_ string: String) throws {
        guard let data = string.data(using: String.Encoding.utf8) else {
            throw FourCharCodeError.invalidSequence
        }
        try self.init(data)
    }

    static func ==(lhs: FourCharCode, rhs: FourCharCode) -> Bool {
        return lhs.bytes == rhs.bytes
    }

    var hashValue: Int {
        return (Int(bytes[0]) << 24) + (Int(bytes[1]) << 16) + (Int(bytes[2]) << 8) + (Int(bytes[3]))
    }

    var description: String {
        let options = MacOSRomanConversionOptions(filterControlCharacters: true, filterFilesystemUnsafeCharacters: false, filterNonASCIICharacters: false, replacementMacOSRomanByte: MacOSRomanByteQuestionMark)
        return stringFromMacOSRomanBytes(bytes, options: options)
    }
}
