//
//  StringFunctions.swift
//  SwresTools
//

import Foundation

private let MinimumDisplayableByteValue: UInt8 = 32

let MacOSRomanByteFullStop: UInt8 = 0x2E
let MacOSRomanByteQuestionMark: UInt8 = 0x3F

struct MacOSRomanConversionOptions {
    let filterControlCharacters: Bool
    let filterFilesystemUnsafeCharacters: Bool
    let filterNonASCIICharacters: Bool
    let replacementMacOSRomanByte: UInt8?
}

func stringFromMacOSRomanBytes(_ buffer: Buffer<UInt8>, options: MacOSRomanConversionOptions) -> String {
    let filterControlCharacters = options.filterControlCharacters || options.filterFilesystemUnsafeCharacters

    let filteredBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: buffer.count + 1)
    defer {
        filteredBytes.deallocate(capacity: buffer.count + 1)
    }

    var filteredByteIterator = filteredBytes

    @inline(__always) func writeFilteredByte(_ byte: UInt8) {
        filteredByteIterator.pointee = byte
        filteredByteIterator += 1
    }

    var bufferPointer = buffer.pointer
    let endPointer = buffer.pointer + buffer.count

    while bufferPointer < endPointer {
        var replaceCharacter = false
        let byte = bufferPointer.pointee

        // SPACE, DELETE
        if filterControlCharacters, byte < 0x20 || byte == 0x7F {
            replaceCharacter = true
        }
        // DELETE
        else if options.filterNonASCIICharacters, byte > 0x7F {
            replaceCharacter = true
        }
        // ASTERISK, FULL STOP, SOLIDUS, COLON, REVERSE SOLIDUS, TILDE
        // Some of these aren't technically unsafe, but they can cause issues in the
        // shell or Finder, such as a period at the start of a file or a tilde.
        else if options.filterFilesystemUnsafeCharacters, byte == 0x2A || byte == 0x2E || byte == 0x2F || byte == 0x3A || byte == 0x5C || byte == 0x7E {
            replaceCharacter = true
        }

        if replaceCharacter, let unwrappedReplacementByte = options.replacementMacOSRomanByte {
            writeFilteredByte(unwrappedReplacementByte)
        } else if !replaceCharacter {
            writeFilteredByte(byte)
        }

        bufferPointer += 1
    }

    filteredByteIterator.pointee = 0

    let cStringPointer = UnsafeRawPointer(filteredBytes).assumingMemoryBound(to: CChar.self)
    return String(cString: cStringPointer, encoding: String.Encoding.macOSRoman)!
}

func stringFromMacOSRomanBytes(_ data: Data, options: MacOSRomanConversionOptions) -> String {
    return data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
        let buffer = Buffer(pointer: bytes, count: data.count)
        return stringFromMacOSRomanBytes(buffer, options: options)
    }
}

func filesystemSafeString(_ data: Data) -> String {
    let options = MacOSRomanConversionOptions(filterControlCharacters: true, filterFilesystemUnsafeCharacters: true, filterNonASCIICharacters: false, replacementMacOSRomanByte: nil)
    return stringFromMacOSRomanBytes(data, options: options)
}

extension String {
    func copyCString() -> ManagedUnsafeMutablePointer<Int8> {
        return self.withCString({ (cString: UnsafePointer<Int8>) -> ManagedUnsafeMutablePointer<Int8> in
            return ManagedUnsafeMutablePointer(adoptPointer: strdup(cString))
        })
    }
}

struct StringAndCString {
    let string: String
    let cString: ManagedUnsafeMutablePointer<CChar>

    init(_ string: String) {
        self.string = string
        cString = string.copyCString()
    }
}
