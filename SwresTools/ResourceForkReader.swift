//
//  ResourceManager.swift
//  SwresTools
//

// Resource Map documentation comes from Inside Macintosh: More Macintosh Toolbox (1993).

import Foundation

typealias ResourcesByType = Dictionary<FourCharCode, Array<Resource>>

enum ResourceForkReaderError: NestingSwresError {
    case emptyResourceFork
    case couldntReadResourceFork(underlyingError: Error?)
    case invalidFormat(underlyingError: SeekableReaderError)
    case other

    var description: String {
        switch self {
        case .emptyResourceFork:
            return "The resource fork is empty."
        case .couldntReadResourceFork(_):
            return "Couldn't read resource fork."
        case .invalidFormat(_):
            return "Input file is corrupted or not a resource fork."
        case .other :
            return "An unexpected error happend while reading the resource fork."
        }
    }

    var underlyingError: Error? {
        switch self {
        case .couldntReadResourceFork(let subError):
            return subError
        case .invalidFormat(let subError):
            return subError
        default:
            return nil
        }
    }
}

// The resource header is:
// * Offset from beginning of resource fork to resource data (4)
// * Offset from beginning of resource fork to resource map (4)
// * Length of resource data (4)
// * Length of resource map (4)
func readResourceFork(_ path: URL) throws -> ResourcesByType {
    let data = try _readResourceFork(path)

    do {
        var reader = SeekableReader(data)
        let dataOffset = try reader.readInt32()
        let mapOffset = try reader.readInt32()
        return try _parseResourceMap(reader: reader, dataOffset: dataOffset, mapOffset: mapOffset)
    } catch let error as SeekableReaderError {
        throw ResourceForkReaderError.invalidFormat(underlyingError: error)
    } catch {
        assertionFailure()
        throw ResourceForkReaderError.other
    }
}

func _readResourceFork(_ path: URL) throws -> Data {
    var error: Error?

    guard let data = ["..namedfork/rsrc", ""].firstSome({ (suffix: String) -> Data? in
        let url = path.appendingPathComponent(suffix)

        var data: Data?
        do {
            data = try Data(contentsOf: url)
        } catch let lastError {
            error = lastError
        }

        if data != nil && data!.count == 0 {
            error = ResourceForkReaderError.emptyResourceFork
            data = nil
        }

        return data
    }) else {
        throw ResourceForkReaderError.couldntReadResourceFork(underlyingError: error)
    }

    return data
}

// The resource map is:
// * Reserved for copy of resource header (16)
// * Reserved for handle to next resource map (4)
// * Reserved for file reference number (2)
// * Resource fork attributes (2)
// * Offset from beginning of map to resource type list (2) [1]
// * Offset from beginning of map to resource name list (2)
// * Number of types in the map minus 1 (2)
// * Resource type list (Variable)
// * Reference lists (Variable)
// * Resource name list (Variable)
//
// Type list starts with:
// * Number of types in the map minus 1
// Each type is:
// * Resource type (4)
// * Number of resources of this type in map minus 1 (2)
// * Offset from beginning of resource type list to reference list for this type (2)
//
// [1] Actually points to the type count, not the start of the variable length type list
func _parseResourceMap(reader: SeekableReader, dataOffset: Int32, mapOffset: Int32) throws -> ResourcesByType {
    var reader = reader
    var resourcesByType = ResourcesByType()

    try reader.seek(mapOffset)
    try reader.skip(16 + 4 + 2 + 2) // Header copy, handle, file no., attributes

    let typeListOffset = mapOffset + Int32(try reader.readInt16())
    let nameListOffset = mapOffset + Int32(try reader.readInt16())

    try reader.seek(typeListOffset)
    let typeCount = try reader.readInt16() + 1

    for _ in 1...typeCount {
        let fourCharCodeBytes = try reader.readBytes(4)
        let type = try FourCharCode(fourCharCodeBytes)
        let resourceCount = try reader.readInt16() + 1
        let referenceListOffset = typeListOffset + Int32(try reader.readInt16())

        resourcesByType[type] = try _parseReferenceList(reader: reader, dataOffset: dataOffset, referenceListOffset: referenceListOffset, nameListOffset: nameListOffset, type: type, resourceCount: resourceCount)
    }

    return resourcesByType
}

// A reference list entry is:
// * Resource ID (2)
// * Offset from beginning of resource name list to resource name (2)
// * Resource attributes (1)
// * Offset from beginning of resource data to data for this resource (3)
// * Reserved for handle to resource (4)
private func _parseReferenceList(reader: SeekableReader, dataOffset: Int32, referenceListOffset: Int32, nameListOffset: Int32, type: FourCharCode, resourceCount: Int16) throws -> Array<Resource> {
    var reader = reader
    var resources = Array<Resource>()
    resources.reserveCapacity(Int(resourceCount))

    try reader.seek(referenceListOffset)
    for _ in 1...resourceCount {
        let identifier = try reader.readInt16()

        var name: Data?
        let nameOffset = try reader.readInt16()
        if nameOffset != -1 {
            let absoluteNameOffset = nameListOffset + Int32(nameOffset)
            try name = _parseName(reader: reader, offset: absoluteNameOffset)
        }

        try reader.skip(1) // Resource attributes

        let relativeDataOffset = try reader.readInt24()
        let absoluteDataOffset = dataOffset + Int32(relativeDataOffset)
        let data = try _parseResourceData(reader: reader, offset: absoluteDataOffset)

        let resource = Resource(type: type, identifier: identifier, name: name, data: data)
        resources.append(resource)

        try reader.skip(4) // Handle to resource
    }

    return resources
}

// A name is:
// * Length of following resource name (1)
// * Characters of resource name (Variable)
private func _parseName(reader: SeekableReader, offset: Int32) throws -> Data {
    var reader = reader
    try reader.seek(offset)
    let length = Int(try reader.readInt8())
    let bytes = try reader.readBytes(length)
    return bytes
}

private func _parseResourceData(reader: SeekableReader, offset: Int32) throws -> Data {
    var reader = reader
    try reader.seek(offset)

    let length = try reader.readInt32()
    return try reader.readBytes(length)
}
