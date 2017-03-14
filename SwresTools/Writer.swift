//
//  Writer.swift
//  SwresTools
//

import Foundation

enum WriterEndianness {
    case littleEndian
    case bigEndian
}

enum WriterError: SwresError {
    case invalidParameter(message: String)
    case alreadyFinalized
    case internalError

    var description: String {
        switch self {
        case .invalidParameter(let message):
            return "Invalid parameter. \(message)"
        case .alreadyFinalized:
            return "The writer has already been finalized."
        case .internalError:
            return "Internal error."
        }
    }
}

class Writer {
    private let _endianness: WriterEndianness
    private var _outputStream: OutputStream
    private var _finalized: Bool = false

    init(endianness: WriterEndianness) {
        _endianness = endianness
        _outputStream = OutputStream.toMemory()
        _outputStream.open()
    }

    private func _unwrapped(_ endianness: WriterEndianness?) -> WriterEndianness {
        if let unwrappedEndianness = endianness {
            return unwrappedEndianness
        }
        return _endianness
    }

    private func _validateNotFinalized() throws {
        guard !_finalized else {
            throw WriterError.alreadyFinalized
        }
    }

    func write(_ value: Int16, endianness: WriterEndianness? = nil) throws {
        try _validateNotFinalized()

        var value = value

        switch _unwrapped(endianness) {
        case .littleEndian:
            value = value.littleEndian
        case .bigEndian:
            value = value.bigEndian
        }

        try withUnsafePointer(to: &value) { (valuePointer: UnsafePointer<Int16>) in
            let bytePointer = UnsafeRawPointer(valuePointer).assumingMemoryBound(to: UInt8.self)
            try _write(bytePointer, length: MemoryLayout<UInt16>.size)
        }
    }

    func write(_ value: Int32, endianness: WriterEndianness? = nil) throws {
        try _validateNotFinalized()

        var value = value

        switch _unwrapped(endianness) {
        case .littleEndian:
            value = value.littleEndian
        case .bigEndian:
            value = value.bigEndian
        }

        try withUnsafePointer(to: &value) { (valuePointer: UnsafePointer<Int32>) in
            let bytePointer = UnsafeRawPointer(valuePointer).assumingMemoryBound(to: UInt8.self)
            try _write(bytePointer, length: MemoryLayout<UInt32>.size)
        }
    }

    func write(_ data: Data) throws {
        try _validateNotFinalized()

        _ = try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
            try _write(pointer, length: data.count)
        }
    }

    func write(ascii: String) throws {
        try _validateNotFinalized()

        guard let data = ascii.data(using: String.Encoding.ascii, allowLossyConversion: true) else {
            throw WriterError.invalidParameter(message: "Invalid ASCII string.")
        }

        try write(data)
    }

    private func _write(_ pointer: UnsafePointer<UInt8>, length: Int) throws {
        let writtenBytes = _outputStream.write(pointer, maxLength: length)
        guard writtenBytes == length else {
            throw WriterError.internalError
        }
    }

    func finalize() throws -> Data {
        try _validateNotFinalized()

        let result = _outputStream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey)
        guard let unwrappedResult = result, let data = unwrappedResult as? Data else {
            throw WriterError.internalError
        }
        _finalized = true
        return data
    }
}
