/// Explicit dismissal survives pointer re-entry and refresh-driven view updates.
public struct InspectorPresentation: Sendable {
    public private(set) var isVisible = false
    private var dismissed = false
    public init() {}
    @discardableResult public mutating func select(explicit: Bool) -> Bool {
        if explicit { dismissed = false }
        guard !dismissed else { return false }
        isVisible = true
        return true
    }
    public mutating func close() { dismissed = true; isVisible = false }
}
