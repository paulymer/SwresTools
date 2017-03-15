//
//  SwresFuse.swift
//  SwresTools
//

import Foundation
import Fuse

struct FuseTask {
    var inputURL: URL?
    var includeTranslations: Bool = false
    var allowPossibleTranslations: Bool = false
    var fuseArgs: ManagedUnsafeMutablePointer<fuse_args>?
}

struct CommandLineOption {
    let template: String
    let key: CommandLineKey
}

enum CommandLineKey: Int32 {
    case fuse_opt_key_keep = -3
    case fuse_opt_key_nonopt = -2
    case fuse_opt_key_opt = -1
    case help = 1
    case includeTranslations
    case allowPossibleTranslations
}

var rootNode: FilesystemNode?
let currentDirectoryCString = ".".copyCString()
let parentDirectoryCString = "..".copyCString()

func printUsageAndExit(status: Int32 = EXIT_SUCCESS) -> Never {
    let processName = ProcessInfo.processInfo.processName

    print("Mount a resource fork with FUSE.")
    print("Usage: \(processName) [options] resourcefile mountpoint")
    print("Options:")
    print("  -h          Show this help message")
    print("  -c          Attempt to convert resources into more modern or portable formats.")
    print("  -C          Also use best guess conversions.")

    exit(status)
}

func dieWithMessage(_ message: String) -> Never {
    print(message)
    exit(EXIT_FAILURE)
}

func withFuseOptions(_ options: Array<CommandLineOption>, _ block: (UnsafePointer<fuse_opt>) -> Void) {
    var cStringPool = Array<ManagedUnsafeMutablePointer<Int8>>()

    var fuseOptions = ContiguousArray<fuse_opt>()
    fuseOptions.reserveCapacity(options.count)

    for option in options {
        let cString = option.template.copyCString()
        cStringPool.append(cString)

        let fuseOption = fuse_opt(templ: UnsafePointer(cString.pointer), offset: UInt(UInt32(bitPattern: -1)), value: option.key.rawValue)
        fuseOptions.append(fuseOption)
    }

    let nullOption = fuse_opt(templ: nil, offset: 0, value: 0)
    fuseOptions.append(nullOption)

    fuseOptions.withUnsafeBufferPointer { (fuseOptionsBufferPointer: UnsafeBufferPointer<fuse_opt>) in
        guard let fuseOptionsPointer = fuseOptionsBufferPointer.baseAddress else {
            dieWithMessage("Error setting up option parsing.")
        }
        block(fuseOptionsPointer)
    }
}

func taskForArguments() -> FuseTask {
    var task = FuseTask()

    let options = [
        CommandLineOption(template: "-h", key: CommandLineKey.help),
        CommandLineOption(template: "-c", key: CommandLineKey.includeTranslations),
        CommandLineOption(template: "-C", key: CommandLineKey.allowPossibleTranslations),
        CommandLineOption(template: "-d", key: CommandLineKey.fuse_opt_key_keep),
    ]

    let args = malloc(MemoryLayout<fuse_args>.size).assumingMemoryBound(to: fuse_args.self)
    args.pointee.argc = CommandLine.argc
    args.pointee.argv = CommandLine.unsafeArgv
    args.pointee.allocated = 0

    withFuseOptions(options, { (fuseOptions: UnsafePointer<fuse_opt>) in
        let parseResult = fuse_opt_parse(args, &task, fuseOptions, { (context: UnsafeMutableRawPointer?, arg: UnsafePointer<Int8>?, key: Int32, args: UnsafeMutablePointer<fuse_args>?) -> Int32 in
            guard let taskRawPointer = UnsafeMutableRawPointer(context) else {
                dieWithMessage("Error parsing arguments. Received a NULL context pointer from FUSE.")
            }
            let taskPointer = taskRawPointer.bindMemory(to: FuseTask.self, capacity: 1)

            guard let arg = arg else {
                dieWithMessage("Error parsing arguments. Received a NULL argument from FUSE.")
            }
            guard let option = String(cString: arg, encoding: String.Encoding.ascii) else {
                dieWithMessage("Error parsing arguments. Argument encoding unrecognized.")
            }

            guard let key = CommandLineKey(rawValue: key) else {
                dieWithMessage("Unexpected key from FUSE.")
            }

            switch key {
            case .fuse_opt_key_nonopt:
                if taskPointer.pointee.inputURL == nil {
                    taskPointer.pointee.inputURL = URL(fileURLWithPathExpandingTilde: option)
                    return 0
                }
                return 1
            case .fuse_opt_key_opt:
                print("Unrecognized option \(option).")
                printUsageAndExit(status: EXIT_FAILURE)
            case .help:
                printUsageAndExit()
            case .includeTranslations:
                taskPointer.pointee.includeTranslations = true
                return 0
            case .allowPossibleTranslations:
                taskPointer.pointee.includeTranslations = true
                taskPointer.pointee.allowPossibleTranslations = true
                return 0
            default:
                dieWithMessage("Unexpected key from FUSE.")
            }
            return 1
        })

        if parseResult != 0 {
            print("Failed to parse optinos.")
            exit(EXIT_FAILURE)
        }
    })

    fuse_opt_add_arg(args, "-s")
    fuse_opt_add_arg(args, "-f")

    task.fuseArgs = ManagedUnsafeMutablePointer(adoptPointer: args)
    return task
}

func getAttr(path: UnsafePointer<Int8>?, stbuf: UnsafeMutablePointer<stat>?) -> Int32 {
    guard let rootNode = rootNode else {
        dieWithMessage("No filesystem root note was created.")
    }
    guard let path = path, let stbuf = stbuf else {
        dieWithMessage("Received null parameter from FUSE.")
    }

    guard let node = rootNode.nodeAtPath(path) else {
        return -ENOENT
    }

    stbuf.pointee.st_mode = node.stMode()
    stbuf.pointee.st_nlink = node.stLinkCount()
    stbuf.pointee.st_size = node.stSize()
    stbuf.pointee.st_uid = getuid()
    stbuf.pointee.st_gid = getgid()

    return 0
}

func readDir(path: UnsafePointer<Int8>?, buf: UnsafeMutableRawPointer?, filler: fuse_fill_dir_t?, offset: off_t, fi: UnsafeMutablePointer<fuse_file_info>?) -> Int32 {
    guard let rootNode = rootNode else {
        dieWithMessage("No filesystem root note was created.")
    }
    guard let path = path, let buf = buf, let filler = filler else {
        dieWithMessage("Received null parameter from FUSE.")
    }

    guard let node = rootNode.nodeAtPath(path) else {
        return -ENOENT
    }

    @inline(__always) func appendEntry(filename: ManagedUnsafeMutablePointer<Int8>) {
        guard filler(buf, filename.pointer, nil, 0) == 0 else {
            // TODO: Figure out how to correctly support large directories.
            dieWithMessage("readDir buffer is full.")
        }
    }

    switch node {
    case .file:
        return -ENOENT
    case .folder(_, let children):
        appendEntry(filename: parentDirectoryCString)
        appendEntry(filename: currentDirectoryCString)
        for (_, child) in children {
            appendEntry(filename: child.cStringName)
        }
    }

    return 0
}

func openFile(path: UnsafePointer<Int8>?, fi: UnsafeMutablePointer<fuse_file_info>?) -> Int32 {
    guard let rootNode = rootNode else {
        dieWithMessage("No filesystem root note was created.")
    }
    guard let path = path, let fi = fi else {
        dieWithMessage("Received null parameter from FUSE.")
    }

    guard let _ = rootNode.nodeAtPath(path) else {
        return -ENOENT
    }

    guard fi.pointee.flags & 3 == O_RDONLY else {
        return -EACCES
    }

    return 0
}

func readFile(path: UnsafePointer<Int8>?, buf: UnsafeMutablePointer<Int8>?, size: size_t, offset: off_t, fi: UnsafeMutablePointer<fuse_file_info>?) -> Int32 {
    guard let rootNode = rootNode else {
        dieWithMessage("No filesystem root note was created.")
    }
    guard let path = path else {
        dieWithMessage("Received null parameter from FUSE.")
    }

    guard let node = rootNode.nodeAtPath(path) else {
        return -ENOENT
    }

    switch node {
    case .folder:
        return -ENOENT
    case .file(_, let data):
        let length = data.count
        let offset = Int(offset)
        guard length > offset else {
            return 0
        }
        let bytesCopied = min(length - offset, size)
        data.withUnsafeBytes { (dataBytes: UnsafePointer<Int8>) -> Void in
            memcpy(buf, dataBytes + offset, bytesCopied)
        }
        return Int32(bytesCopied)
    }
}

func run(_ task: FuseTask) -> Int32 {
    guard let inputURL = task.inputURL else {
        dieWithMessage("Missing inputURL in task.")
    }

    do {
        let resourcesByType = try readResourceFork(inputURL)
        rootNode = filesystemNode(resourcesByType, includeTranslations: task.includeTranslations)

        var operations = fuse_operations()
        operations.getattr = getAttr
        operations.readdir = readDir
        operations.open = openFile
        operations.read = readFile

        guard let args = task.fuseArgs?.pointer else {
            dieWithMessage("Failed to construct arguments to pass to FUSE.")
        }

        let result = fuse_main_real(args.pointee.argc, args.pointee.argv, &operations, MemoryLayout.size(ofValue: operations), nil)
        return result
    } catch {
        dieWithMessage(error.shortDescription(withUnderlyingError: true))
    }
}

func filesystemNode(_ resourcesByType: ResourcesByType, includeTranslations: Bool) -> FilesystemNode {
    let folders = resourcesByType.map { (type: FourCharCode, resources: Array<Resource>) -> FilesystemNode in
        let folderName = filesystemSafeString(type.bytes)
        let children = resources.flatMap { (resource: Resource) -> Array<FilesystemNode> in
            return filesystemNodes(resource, includeTranslations: includeTranslations)
        }

        return FilesystemNode(name: folderName, children: children)
    }

    return FilesystemNode(name: "ROOT", children: folders)
}

func filesystemNodes(_ resource: Resource, includeTranslations: Bool) -> Array<FilesystemNode> {
    var nodes = Array<FilesystemNode>()

    var filename = "\(resource.identifier)"
    if let name = resource.name {
        let sanitizedName = filesystemSafeString(name)
        filename += " \(sanitizedName)"
    }
    nodes.append(FilesystemNode(name: filename, data: resource.data))

    if (includeTranslations) {
        let translatorManager = TranslatorManager.sharedInstance
        let translationResults = translatorManager.translate(resource, includeTranslators: TranslatorFilter.likelyAndPossibleTranslators)

        let translationNodes = translationResults.flatMap { (translationResult: TranslationResult) -> FilesystemNode? in
            switch translationResult {
            case .translated(let translation):
                let translatedFilename = filename + ".\(translation.suggestedFileExtension)"
                return FilesystemNode(name: translatedFilename, data: translation.data)
            case .error(let error):
                print(error.shortDescription(withUnderlyingError: true))
                return nil
            }
        }

        nodes.append(contentsOf: translationNodes)
    }

    return nodes
}

func swresFuseMain() -> Int32 {
    let task = taskForArguments()
    return run(task)
}
