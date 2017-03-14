//
//  ErrorExtras.swift
//  SwresTools
//

protocol SwresError: Error, CustomStringConvertible {
}

protocol NestingSwresError: SwresError {
    var underlyingError: Error? { get }
}

extension Error {
    func shortDescription(withUnderlyingError: Bool = false) -> String {
        switch self {
        case let error as NestingSwresError:
            var string = error.description
            if let underlyingError = error.underlyingError, withUnderlyingError == true {
                string += "\n" + underlyingError.shortDescription(withUnderlyingError: true)
            }
            return string
        case let error as SwresError:
            return error.description
        default:
            return localizedDescription
        }
    }
}
