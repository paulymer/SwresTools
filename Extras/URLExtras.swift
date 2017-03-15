//
//  URLExtras.swift
//  SwresTools
//

import Foundation

extension URL {
    init(fileURLWithPathExpandingTilde filePath: String) {
        let nsStringFilePath = filePath as NSString
        let expandedFilePath = nsStringFilePath.expandingTildeInPath
        self.init(fileURLWithPath: expandedFilePath)
    }
}
