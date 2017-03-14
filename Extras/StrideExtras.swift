//
//  StrideExtras.swift
//  SwresTools
//

func offsetAndLengthStride(from: Int, to: Int, by: Int, _ block: (Int, Int) -> Void) {
    for offset in stride(from: from, to: to, by: by) {
        block(offset, min(by, to - offset))
    }
}
