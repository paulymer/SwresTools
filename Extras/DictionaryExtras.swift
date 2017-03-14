//
//  DictionaryExtras.swift
//  SwresTools
//

extension Dictionary {
    init(_ elements: Array<Element>){
        self.init()
        for (key, value) in elements {
            self[key] = value
        }
    }

    func flatMap(transform: (Key, Value) -> (Key, Value)?) -> Dictionary<Key, Value> {
        return Dictionary(self.flatMap(transform))
    }
}
    
