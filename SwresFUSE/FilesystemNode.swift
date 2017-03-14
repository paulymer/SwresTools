//
//  FilesystemNode.swift
//  SwresTools
//

import Foundation

enum FilesystemNode {
    case folder(name: StringAndCString, children: Dictionary<String, FilesystemNode>)
    case file(name: StringAndCString, data: Data)

    var cStringName: ManagedUnsafeMutablePointer<Int8> {
        switch self {
        case .folder(let name, _):
            return name.cString
        case .file(let name, _):
            return name.cString
        }
    }

    var name: String {
        switch self {
        case .folder(let name, _):
            return name.string
        case .file(let name, _):
            return name.string
        }
    }

    init(name: String, data: Data) {
        self = .file(name: StringAndCString(name), data: data)
    }

    init(name: String, children: Array<FilesystemNode>) {
        let nameAndChildTuples = children.map { (child: FilesystemNode) -> (String, FilesystemNode) in
            return (child.name, child)
        }
        self = .folder(name: StringAndCString(name), children: Dictionary(nameAndChildTuples))
    }

    func nodeAtPath(_ path: UnsafePointer<Int8>) -> FilesystemNode? {
        guard let pathString = String(cString: path, encoding: String.Encoding.utf8) else {
            return nil
        }
        return nodeAtPath(pathString)
    }

    func nodeAtPath(_ path: String) -> FilesystemNode? {
        let pathComponents = path.components(separatedBy: "/").filter { (pathComponent: String) -> Bool in
            pathComponent.characters.count > 0
        }

        return _nodeAtPath(pathComponents[0 ..< pathComponents.endIndex])
    }

    private func _nodeAtPath(_ pathComponents: ArraySlice<String>) -> FilesystemNode? {
        guard let nextComponent = pathComponents.first else {
            return self
        }

        switch self {
        case .file:
            guard pathComponents.count == 1 && nextComponent == self.name else {
                return nil
            }
            return self
        case .folder(_, let children):
            guard let child = children[nextComponent] else {
                return nil
            }
            return child._nodeAtPath(pathComponents[1 ..< pathComponents.endIndex])
        }
    }

    func isFolder() -> Bool {
        switch self {
        case .folder:
            return true
        default:
            return false
        }
    }

    func stLinkCount() -> nlink_t {
        switch self {
        case .file:
            return 1
        case .folder(_, let children):
            let childFolders = children.filter { (_, child: FilesystemNode) in
                return child.isFolder()
            }
            return nlink_t(childFolders.count + 2)
        }
    }

    func stMode() -> mode_t {
        switch self {
        case .file:
            return S_IFREG | 0o0444
        case .folder:
            return S_IFDIR | 0o0555
        }
    }

    func stSize() -> off_t {
        switch self {
        case .file(_, let data):
            return off_t(data.count)
        case .folder:
            return 0
        }
    }
}
