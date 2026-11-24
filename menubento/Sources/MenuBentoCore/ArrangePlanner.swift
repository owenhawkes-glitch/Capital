import Foundation

/// Works out which items to drag to turn one order into another with as
/// few moves as possible.
///
/// The items already in the right relative order (the longest increasing
/// run of their current positions, read in target order) stay put; only
/// the rest are moved, each next to a neighbour that is already settled.
public enum ArrangePlanner {
    public enum Anchor: Equatable, Sendable {
        case leftOf(ItemRef)
        case rightOf(ItemRef)
    }

    /// The refs (present in both lists) that can stay where they are.
    /// `pinned` refs can't be moved, so they are always kept.
    public static func stable(current: [ItemRef], target: [ItemRef], pinned: Set<ItemRef> = []) -> Set<ItemRef> {
        let position = Dictionary(current.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let wanted = target.filter { position[$0] != nil }
        // Longest increasing subsequence of current positions, preferring
        // runs that include pinned items (weighted heavily).
        let n = wanted.count
        guard n > 0 else { return [] }
        var best = [Int](repeating: 0, count: n), prev = [Int](repeating: -1, count: n)
        for i in 0..<n {
            let weight = pinned.contains(wanted[i]) ? 1000 : 1
            best[i] = weight
            for j in 0..<i where position[wanted[j]]! < position[wanted[i]]! && best[j] + weight > best[i] {
                best[i] = best[j] + weight
                prev[i] = j
            }
        }
        var i = best.indices.max { best[$0] < best[$1] }!
        var keep: Set<ItemRef> = []
        while i >= 0 {
            keep.insert(wanted[i])
            i = prev[i]
        }
        return keep
    }

    /// Where to drop `ref` given what's already settled: just left of the
    /// nearest settled item to its right in the target, or just right of
    /// the nearest settled item to its left.
    public static func anchor(for ref: ItemRef, target: [ItemRef], settled: Set<ItemRef>) -> Anchor? {
        guard let i = target.firstIndex(of: ref) else { return nil }
        if let right = target[(i + 1)...].first(where: settled.contains) { return .leftOf(right) }
        if let left = target[..<i].last(where: settled.contains) { return .rightOf(left) }
        return nil
    }

    /// True when `ref` sits where the target wants it among `settled` items.
    public static func isPlaced(_ ref: ItemRef, current: [ItemRef], target: [ItemRef], settled: Set<ItemRef>) -> Bool {
        let among = settled.union([ref])
        let now = current.filter(among.contains)
        let want = target.filter(among.contains)
        return now == want
    }
}
