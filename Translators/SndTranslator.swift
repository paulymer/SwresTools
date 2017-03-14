//
//  SndTranslator.swift
//  SwresTools
//

// This is an incredibly basic converter for `Snd ' resources. It does not attempt to actually
// parse headers or commands property. It does not recognize extended headers. It does not
// do anything useful for anything other than the most basic, 8-bit mono PCM samples with
// super boring and obvious headers.

// Resournce information comes from Inside Macintosh (1993).

import Foundation

private let SndResourceType: FourCharCode = try! FourCharCode("snd ")
private let SuggestedFileExtension: String = "wav"

private let WAVHeaderCount = 44

private struct SndResource {
    let sampleRate: Int
    let data: Data
}

struct SndTranslator: Translator {
    func compatibilityWith(resource: Resource) -> TranslatorCompatibility {
        if resource.type == SndResourceType {
            return TranslatorCompatibility.likelyCompatible
        }
        return TranslatorCompatibility.notCompatible
    }

    func translate(resource: Resource) throws -> Translation {
        let reader = SeekableReader(resource.data)

        do {
            let sndResource = try _readSndResource(reader)
            let data = try _wavData(sndResource)
            return Translation(data: data, suggestedFileExtension: SuggestedFileExtension)
        } catch let error {
            throw TranslatorError.invalidResource(reason: "Failed to parse snd resource.", underlyingError: error)
        }
    }

    private func _readSndResource(_ reader: SeekableReader) throws -> SndResource {
        var reader = reader
        let format = try reader.readInt16()

        guard format == 1 || format == 2 else {
            throw TranslatorError.invalidResource(reason: "Unknown snd format \(format)", underlyingError: nil)
        }
        guard format == 1 else {
            throw TranslatorError.unsupportedResource(reason: "Format 2 snd resources are not supported.")
        }

        let dataFormatCount = try reader.readInt16()
        guard dataFormatCount > 0 else {
            throw TranslatorError.unsupportedResource(reason: "The resource doesn't contain any data formats.")
        }
        guard dataFormatCount == 1 else {
            throw TranslatorError.unsupportedResource(reason: "The author hasn't read the spec closely enough to understand what to do when the resource contains more than one data format.")
        }

        let dataType = try reader.readInt16()
        guard dataType == 5 else {
            throw TranslatorError.unsupportedResource(reason: "Only sampled sound data (type 0x0005) is supported.")
        }

        // Skip the sound channel init options.
        try reader.skip(4)

        let commandCount = try reader.readInt16()
        guard commandCount == 1 else {
            throw TranslatorError.unsupportedResource(reason: "The author hasn't read the spec closely enough to understand what to do when the resource contains more than one sound command.")
        }

        let command = try reader.readInt16()
        guard command == Int16(bitPattern: 0x8051) else {
            throw TranslatorError.unsupportedResource(reason: "Only bufferCmd commands are supported.")
        }

        // param1 seems to be unused for this command.
        try reader.skip(2)
        let soundHeaderOffset = try reader.readInt32()

        try reader.seek(soundHeaderOffset)
        let sampleDataPointer = try reader.readInt32()
        guard sampleDataPointer == 0 else {
            throw TranslatorError.unsupportedResource(reason: "The author hasn't read the spec closely enough to understand what a non-zero sample data pointer means.")
        }

        let sampleByteLength = try reader.readInt32()
        guard sampleByteLength > 0 else {
            throw TranslatorError.invalidResource(reason: "Sample has a negative length.", underlyingError: nil)
        }

        // The sample rate is an unsigned 16.16 fixed point integer. Flooring the frequency loses
        // information but the precision loss is less than one hundredth of one percent and WAV
        // maybe doesn't support fractional frequencies?
        let sampleRateFixed = try reader.readInt32()
        let sampleRate = Int(sampleRateFixed >> 16)

        // Skip the two loop point parameters
        try reader.skip(8)

        let sampleEncoding = try reader.readInt8()
        guard sampleEncoding == 0 else {
            throw TranslatorError.unsupportedResource(reason: "Encoded samples are not supported.")
        }

        // Skip baseFrequency
        try reader.skip(1)

        let sampleData = try reader.readBytes(sampleByteLength)

        return SndResource(sampleRate: sampleRate, data: sampleData)
    }

    private func _wavData(_ sndResource: SndResource) throws -> Data {
        let writer = Writer(endianness: .littleEndian)

        let data = sndResource.data
        let dataCount = data.count
        let wavFileSize = dataCount + WAVHeaderCount

        let sampleRate = sndResource.sampleRate

        // The header ChunkSize does not include the first ChunkID and size, i.e.
        // it's the file size minus the first 8 bytes
        try writer.write(ascii: "RIFF")
        try writer.write(Int32(wavFileSize - 8))
        try writer.write(ascii: "WAVE")

        try writer.write(ascii: "fmt ")
        try writer.write(Int32(16))         // Subchunk size
        try writer.write(Int16(1))          // AudioFormat: PCM
        try writer.write(Int16(1))          // Channel count
        try writer.write(Int32(sampleRate))
        try writer.write(Int32(sampleRate)) // Bytes per second
        try writer.write(Int16(1))          // Block alignment
        try writer.write(Int16(8))          // Bits per sample

        try writer.write(ascii: "data")
        try writer.write(Int32(dataCount))
        try writer.write(data)

        return try writer.finalize()
    }
}
