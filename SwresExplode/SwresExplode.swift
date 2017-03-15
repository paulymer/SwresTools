//
//  SwresExplode.swift
//  SwresTools
//

import Foundation

struct ExplodeTask {
    var printResources: Bool = false
    var dumpResources: Bool = false
    var overwriteExistingFiles: Bool = false
    var translatorFilter: TranslatorFilter = TranslatorFilter.noTranslators
    var identifierFilter: Int16?
    var typeFilter: FourCharCode?
    var inputURL: URL?
    var outputFolder: URL = URL(fileURLWithPath: "SwresExplode")
}

func printUsageAndExit(status: Int32 = EXIT_SUCCESS) -> Never {
    let processName = ProcessInfo.processInfo.processName

    print("Extract Macintosh Toolbox resources.")
    print("Usage: \(processName) [options] resourcefile")
    print("Options:")
    print("  -h          Show this help message")
    print("Filtering Options:")
    print("  -i [id]     Filter by resource identifier.")
    print("  -t [xxxx]   Filter by resource type.")
    print("Dumping Options:")
    print("  -p          Print resources to standard output.")
    print("  -d          Dump resources to files.")
    print("  -o          Output directory for the dumped resource.")
    print("  -f          Overwrite existing files when dumping.")
    print("  -c          Attempt to convert resources into more modern or portable formats.")
    print("  -C          Also use best guess conversions.")
    print("Examples:")
    print("  \(processName) resourcefile          List all of the types.")
    print("  \(processName) -d -t 'snd '          Dump all `snd ' resources.")
    print("  \(processName) -d -t 'snd ' -i 1000  Dump the `snd ' resource with id 1000.")
    print("  \(processName) -d -o /tmp/foo        Dump all resources to the directory /tmp/foo.")

    exit(status)
}

func taskForArguments() -> ExplodeTask {
    var task = ExplodeTask()
    let argc = CommandLine.argc
    opterr = 0

    while true {
        let option = getopt(argc, CommandLine.unsafeArgv, "hi:t:pdfcCo:")
        if option == -1 {
            break
        }

        let optionScalar = UnicodeScalar(Int(option))!
        switch optionScalar {
        case UnicodeScalar("h"):
            printUsageAndExit()
        case UnicodeScalar("i"):
            let identifierNumber = String(cString: optarg)
            task.identifierFilter = Int16(identifierNumber)
        case UnicodeScalar("t"):
            do {
                task.typeFilter = try FourCharCode(optarg)
            } catch FourCharCodeError.invalidSequence {
                print("Invalid type filter.");
                printUsageAndExit(status: EXIT_FAILURE)
            } catch {
                print("Unexpected error parsing type filter.")
                printUsageAndExit(status: EXIT_FAILURE)
            }
        case UnicodeScalar("p"):
            task.printResources = true
        case UnicodeScalar("d"):
            task.dumpResources = true
        case UnicodeScalar("o"):
            task.outputFolder = URL(fileURLWithPathExpandingTilde: String(cString: optarg))
        case UnicodeScalar("f"):
            task.overwriteExistingFiles = true
        case UnicodeScalar("c"):
            task.translatorFilter = max(task.translatorFilter, TranslatorFilter.onlyLikelyTranslators)
        case UnicodeScalar("C"):
            task.translatorFilter = max(task.translatorFilter, TranslatorFilter.likelyAndPossibleTranslators)
        case UnicodeScalar("?"):
            let unknownOption = UnicodeScalar(Int(optopt))!
            if unknownOption == UnicodeScalar("i") || unknownOption == UnicodeScalar("t") {
                print("Option -\(unknownOption) requires an argument.")
            } else {
                print("Unknown option -\(unknownOption.escaped(asASCII: true)).")
            }
            printUsageAndExit(status: EXIT_FAILURE)
        default:
            printUsageAndExit(status: EXIT_FAILURE)
        }
    }

    guard optind < argc else {
        print("No input file specified.")
        printUsageAndExit(status: EXIT_FAILURE)
    }

    let inputPathBytes = CommandLine.unsafeArgv[Int(optind)]!
    let inputPath = String(cString: inputPathBytes)
    task.inputURL = URL(fileURLWithPathExpandingTilde: inputPath)

    return task
}

func run(_ task: ExplodeTask) -> Int32 {
    let resourcesByType = read(task)
    process(task: task, resourcesByType: resourcesByType)
    return EXIT_SUCCESS
}

func read(_ task: ExplodeTask) -> ResourcesByType {
    do {
        return try readResourceFork(task.inputURL!)
    } catch let error {
        print(error.shortDescription(withUnderlyingError: true))
        exit(EXIT_FAILURE)
    }
}

func process(task: ExplodeTask, resourcesByType: ResourcesByType) {
    if task.dumpResources {
        do {
            try createOutputDirectory(task: task)
        } catch let error {
            print(error.shortDescription(withUnderlyingError: true))
            exit(EXIT_FAILURE)
        }
    }

    let filteredResourcesByType = filter(resources: resourcesByType, task: task)
    for (_, resources) in filteredResourcesByType {
        for resource in resources {
            print(format(resource))

            if task.printResources {
                print(format(resource.data))
            }

            if task.dumpResources {
                dump(task: task, resource: resource)
            }
        }
    }
}

enum OutputDirectoryError: NestingSwresError {
    case directoryIsNotAFolder
    case directoryExists
    case couldntCreateDirectory(underlyingError: Error)

    var underlyingError: Error? {
        switch self {
        case .couldntCreateDirectory(let underlyingError):
            return underlyingError
        default:
            return nil
        }
    }

    var description: String {
        switch self {
        case .directoryIsNotAFolder:
                return "Output directory is not a folder."
        case .directoryExists:
                return "Output directory already exists. Use -f to overwrite existing files."
        case .couldntCreateDirectory:
                return "Couldn't create output directory."
        }
    }
}

func createOutputDirectory(task: ExplodeTask) throws {
    let fileManager = FileManager.default
    let outputDirectoryPath = task.outputFolder.path

    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: outputDirectoryPath, isDirectory: &isDirectory) {
        guard isDirectory.boolValue else {
            throw OutputDirectoryError.directoryIsNotAFolder
        }

        guard task.overwriteExistingFiles else {
            throw OutputDirectoryError.directoryExists
        }
    }

    do {
        try fileManager.createDirectory(at: task.outputFolder, withIntermediateDirectories: true, attributes: nil)
    } catch let error {
        throw OutputDirectoryError.couldntCreateDirectory(underlyingError: error)
    }
}

func dump(task: ExplodeTask, resource: Resource) {
    let (folderURL, fileURL) = explodedLocation(task: task, resource: resource)

    let fileManager = FileManager.default
    do {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        try resource.data.write(to: fileURL)
    } catch let error {
        print("Couldn't dump resource \(resource.type) \(resource.identifier).")
        print(error.shortDescription)
    }

    if task.translatorFilter >= TranslatorFilter.onlyLikelyTranslators {
        let translatorManager = TranslatorManager.sharedInstance
        let translationResults = translatorManager.translate(resource, includeTranslators: task.translatorFilter)

        for translationResult in translationResults {
            switch translationResult {
            case .translated(let translation):
                let outputURL = fileURL.appendingPathExtension(translation.suggestedFileExtension)
                let data = translation.data
                do {
                    try data.write(to: outputURL)
                } catch let error {
                    let resourceDescription = format(resource, short: true)
                    print("Couldn't write translation for resource \(resourceDescription).")
                    print(error.shortDescription(withUnderlyingError: true))
                }
            case .error(let error):
                let resourceDescription = format(resource, short: true)
                print("Failed to translate resource \(resourceDescription).")
                print(error.shortDescription(withUnderlyingError: true))
            }
        }
    }
}

func filter(resources: ResourcesByType, task: ExplodeTask) -> ResourcesByType {
    return resources.flatMap { (type: FourCharCode, resources: Array<Resource>) -> (FourCharCode, Array<Resource>)? in
        if let typeFilter = task.typeFilter, type != typeFilter {
            return nil
        }

        let filteredResources = resources.flatMap { (resource: Resource) -> Resource? in
            if let identifierFilter = task.identifierFilter, resource.identifier != identifierFilter {
                return nil
            }
            return resource
        }

        return (type, filteredResources)
    }
}

func format(_ resource: Resource, short: Bool = false) -> String {
    if short {
        return "'\(resource.type.description)' \(resource.identifier)"
    }

    var string = String(format: "'%@' %7d %8d bytes", resource.type.description, resource.identifier, resource.data.count)
    if let name = resource.stringName {
        string += " \"\(name)\""
    }
    return string
}

func format(_ data: Data) -> String {
    let options = MacOSRomanConversionOptions(filterControlCharacters: true, filterFilesystemUnsafeCharacters: false, filterNonASCIICharacters: true, replacementMacOSRomanByte: MacOSRomanByteFullStop)

    var lines = Array<String>()
    data.withUnsafeBytes { (unsafeBytes: UnsafePointer<UInt8>) in
        offsetAndLengthStride(from: 0, to: data.count, by: 16, { (offset: Int, length: Int) in
            let formattedOffset = format(asHex: offset, length: 8)

            let lineBuffer = Buffer(pointer: unsafeBytes + offset, count: length)
            let formattedLine = format(line: lineBuffer, lineLength: 16)
            let asciiFormattedBytes = stringFromMacOSRomanBytes(lineBuffer, options: options)

            let rowString = "\(formattedOffset): \(formattedLine)  \(asciiFormattedBytes)"
            lines.append(rowString)
        })
    }

    return lines.joined(separator: "\n")
}

// 0-9, A-F
let asciiHexCharacters: Array<CChar> = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66]
let asciiSpace: CChar = 0x20

func format(asHex number: Int, length: Int) -> String {
    assert(length >= 0)

    var number = number
    let stringBufferCapacity = length + 1
    let stringBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: stringBufferCapacity)
    defer {
        stringBuffer.deallocate(capacity: stringBufferCapacity)
    }

    var stringBufferIterator = stringBuffer + length
    stringBufferIterator.pointee = 0
    stringBufferIterator -= 1

    while stringBufferIterator >= stringBuffer {
        stringBufferIterator.pointee = asciiHexCharacters[number % 16]
        number = number / 16
        stringBufferIterator -= 1
    }

    return String(cString: stringBuffer, encoding: String.Encoding.ascii)!
}

func format(line lineBuffer: Buffer<UInt8>, lineLength: Int) -> String {
    assert(lineBuffer.count <= lineLength)

    let lineBytes = lineBuffer.pointer
    let lineBytesCount = lineBuffer.count

    let spacerCount = max(0, (lineLength - 1) / 2)
    let stringBufferSize = lineLength * 2 + spacerCount + 1
    let stringBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: stringBufferSize)
    defer {
        stringBuffer.deallocate(capacity: stringBufferSize)
    }

    var stringBufferIterator = stringBuffer

    @inline(__always) func writeCChar(_ char: CChar) {
        stringBufferIterator.pointee = char
        stringBufferIterator += 1
    }

    for byteIndex in 0..<lineLength {
        if byteIndex % 2 == 0 && byteIndex > 0 {
            writeCChar(asciiSpace)
        }

        if byteIndex < lineBytesCount {
            let byte = lineBytes[byteIndex]
            writeCChar(asciiHexCharacters[Int(byte / 16)])
            writeCChar(asciiHexCharacters[Int(byte % 16)])
        } else {
            writeCChar(asciiSpace)
            writeCChar(asciiSpace)
        }
    }

    writeCChar(0)

    return String(cString: stringBuffer, encoding: String.Encoding.ascii)!
}

func explodedLocation(task: ExplodeTask, resource: Resource) -> (URL, URL) {
    let outputFolder = task.outputFolder
    let typeFolder = outputFolder.appendingPathComponent(filesystemSafeString(resource.type.bytes))
    var filename = "\(resource.identifier)"
    if let name = resource.name {
        let sanitizedName = filesystemSafeString(name)
        filename += " \(sanitizedName)"
    }
    let url = typeFolder.appendingPathComponent(filename)
    return (typeFolder, url)
}

func swresExplodeMain() -> Int32 {
    let task = taskForArguments()
    return run(task)
}
