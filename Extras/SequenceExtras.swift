//
//  SequenceExtras.swift
//  SwresTools
//

extension Sequence {
    func firstSome<ElementOfResult>(_ transform: @escaping (Iterator.Element) -> ElementOfResult?) -> ElementOfResult? {
        return self.lazy.flatMap(transform).first
    }

    func groupBy<ElementOfResult: Hashable>(_ transform: (Iterator.Element) -> ElementOfResult) -> Dictionary<ElementOfResult, Array<Iterator.Element>> {
        var groupedBy: Dictionary<ElementOfResult, Array<Iterator.Element>> = Dictionary()
        for item in self {
            let transformed = transform(item)
            if groupedBy[transformed] == nil {
                groupedBy[transformed] = Array<Iterator.Element>()
            }
            groupedBy[transformed]!.append(item)
        }
        return groupedBy
    }
}
