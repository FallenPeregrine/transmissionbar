/// Stable hash selection independent of row order and window presentation.
public struct TorrentSelection: Sendable {
    public private(set) var ids: Set<String> = []
    public private(set) var primary: String?
    private var anchor: String?
    public init() {}
    public mutating func select(_ id: String, ordered: [String], extend: Bool = false, toggle: Bool = false) {
        if extend, let anchor, let a = ordered.firstIndex(of: anchor), let b = ordered.firstIndex(of: id) {
            let range = Set(ordered[min(a, b)...max(a, b)])
            ids = toggle ? ids.union(range) : range
            primary = id
        } else if toggle {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            primary = ids.contains(id) ? id : ordered.first(where: { ids.contains($0) })
            anchor = primary
        } else {
            ids = [id]; primary = id; anchor = id
        }
    }
    public mutating func selectAll(ordered: [String]) {
        ids = Set(ordered)
        if primary.map({ !ids.contains($0) }) ?? true { primary = ordered.first }
        anchor = primary
    }
    public mutating func contextSelect(_ id: String, ordered: [String]) {
        if ids.contains(id) { primary = id }
        else { select(id, ordered: ordered) }
    }
    public mutating func retain(_ allowed: Set<String>, ordered: [String]) {
        ids.formIntersection(allowed)
        if let primary, !ids.contains(primary) { self.primary = ordered.first(where: { ids.contains($0) }) }
        if let anchor, !ids.contains(anchor) { self.anchor = primary }
    }
    public mutating func clear() { ids = []; primary = nil; anchor = nil }
}
