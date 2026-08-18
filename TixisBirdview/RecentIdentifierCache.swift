//
//  RecentIdentifierCache.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 18.08.26 with the help of Codex (GPT-5.6 Terra Extra High).
//

struct RecentIdentifierCache {
    private let capacity: Int
    private var identifiers = Set<String>()
    private var slots: [String?]
    private var nextEvictionIndex = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        slots = Array(repeating: nil, count: capacity)
    }

    @discardableResult
    mutating func insert(_ identifier: String) -> Bool {
        guard identifiers.insert(identifier).inserted else {
            return false
        }

        if let evictedIdentifier = slots[nextEvictionIndex] {
            identifiers.remove(evictedIdentifier)
        }
        slots[nextEvictionIndex] = identifier
        nextEvictionIndex = (nextEvictionIndex + 1) % capacity
        return true
    }

    func contains(_ identifier: String) -> Bool {
        identifiers.contains(identifier)
    }

    var count: Int {
        identifiers.count
    }
}
