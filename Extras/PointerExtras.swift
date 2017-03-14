//
//  PointerExtras.swift
//  SwresTools
//

import Darwin

// For performance, there are a few places strings are passed around as a base pointer
// and a count of bytes. The Swift standard library includes `UnsafeBufferPointer` and
// `UnsafeMutableBufferPointer` which could wrap that pointer and length, but it's
// surprisingly slow. Replacing that with this tiny `Buffer` struct sped up string
// formatting hotpaths considerably.
struct Buffer<T> {
    let pointer: UnsafePointer<T>
    let count: Int
}

class ManagedUnsafeMutablePointer<T>: Hashable {
    let pointer: UnsafeMutablePointer<T>

    init(adoptPointer: UnsafeMutablePointer<T>) {
        pointer = adoptPointer
    }

    deinit {
        free(pointer)
    }

    var hashValue: Int {
        return pointer.hashValue
    }

    static func ==(lhs: ManagedUnsafeMutablePointer, rhs: ManagedUnsafeMutablePointer) -> Bool {
        return lhs.pointer == rhs.pointer
    }
}
