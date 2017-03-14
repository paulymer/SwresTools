//
//  SeekableReader.swift
//  SwresTools
//

import Foundation

enum SeekableReaderError: SwresError {
    case invalidLocation(Int)
    case invalidRange(location: Int, length: Int)
    case invalidParameter(name: String, value: Any)
    case internalError

    var description: String {
        switch(self) {
        case .invalidLocation(let location):
            return String.init(format: "Invalid seek to location 0x%x.", location)
        case .invalidRange(let location, let length):
            return String.init(format: "Invalid read at location 0x%x with length %d.", location, length)
        case .invalidParameter:
            return "Program error."
        case .internalError:
            return "Internal error."
        }
    }
}

// Assumes big-endian byte order.
struct SeekableReader {
    private let _data: Data
    private var _offset: Int

    init(_ data: Data) {
        _data = data
        _offset = 0
    }

    private mutating func _readUInt32(length: Int) throws -> UInt32 {
        guard length > 0 else {
            assertionFailure()
            throw SeekableReaderError.internalError
        }
        guard _offset + length <= _data.count else  {
            throw SeekableReaderError.invalidRange(location: _offset, length: length)
        }

        var value: UInt32 = 0
        for _ in 1...length {
            let byte = _data[_offset]
            value = (value << 8) + UInt32(byte)
            _offset += 1
        }
        return value
    }

    mutating func readInt8() throws -> Int8 {
        return try Int8(truncatingBitPattern: _readUInt32(length: 1))
    }

    mutating func readInt16() throws -> Int16 {
        return try Int16(truncatingBitPattern: _readUInt32(length: 2))
    }

    mutating func readInt24() throws -> Int32 {
        return try Int32(bitPattern: _readUInt32(length: 3))
    }

    mutating func readInt32() throws -> Int32 {
        return try Int32(bitPattern: _readUInt32(length: 4))
    }

    mutating func readBytes(_ length: Int) throws -> Data {
        guard length > 0 else  {
            throw SeekableReaderError.invalidParameter(name: "length", value: length)
        }
        guard _offset + length <= _data.count else {
            throw SeekableReaderError.invalidRange(location: _offset, length: length)
        }

        let subdata = _data.subdata(in: _offset..<(_offset + length))
        _offset += length
        return subdata
    }

    mutating func readBytes(_ length: Int32) throws -> Data {
        return try readBytes(Int(length))
    }

    mutating func seek(_ offset: Int) throws {
        guard offset >= 0 && offset < _data.count else {
            throw SeekableReaderError.invalidLocation(offset)
        }
        _offset = offset
    }

    mutating func seek(_ offset: Int32) throws {
        try seek(Int(offset))
    }

    mutating func skip(_ offset: Int) throws {
        try(seek(_offset + offset))
    }
}
