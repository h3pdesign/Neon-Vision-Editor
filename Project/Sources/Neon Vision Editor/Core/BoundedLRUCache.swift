/// Owner-isolated value cache. Cost is supplied by the caller; oversized entries
/// are never retained. Reading promotes an entry, replacing releases old cost.
nonisolated struct BoundedLRUCache<Key: Hashable, Value> {
    private var entries: [Key: (value: Value, cost: Int)] = [:]
    private var order: [Key] = []
    private(set) var totalCost = 0
    var count: Int { entries.count }
    let maximumCount: Int
    let maximumCost: Int

    mutating func value(for key: Key) -> Value? {
        guard let entry = entries[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return entry.value
    }

    mutating func remove(_ key: Key) {
        if let entry = entries.removeValue(forKey: key) { totalCost -= entry.cost }
        order.removeAll { $0 == key }
    }

    mutating func remove(where predicate: (Key) -> Bool) {
        for key in order.filter(predicate) { remove(key) }
    }

    mutating func store(_ value: Value, for key: Key, cost: Int) {
        remove(key)
        guard maximumCount > 0, cost >= 0, cost <= maximumCost else { return }
        while count >= maximumCount || totalCost > maximumCost - cost {
            guard let oldest = order.first else { break }
            remove(oldest)
        }
        entries[key] = (value, cost)
        order.append(key)
        totalCost += cost
    }
}
