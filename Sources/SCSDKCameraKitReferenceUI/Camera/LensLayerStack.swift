struct LensLayerStack<Element> {
    private(set) var pinnedBase: Element?
    private(set) var selectedTop: Element?

    var current: Element? {
        selectedTop ?? pinnedBase
    }

    var applied: [Element] {
        [pinnedBase, selectedTop].compactMap { $0 }
    }

    mutating func select(_ element: Element, matches: (Element, Element) -> Bool) {
        if let pinnedBase, matches(pinnedBase, element) {
            selectedTop = nil
        } else {
            selectedTop = element
        }
    }

    @discardableResult
    mutating func pinCurrent(matches: (Element, Element) -> Bool) -> Bool {
        if let pinnedBase {
            if let selectedTop {
                _ = matches(pinnedBase, selectedTop)
            }
            return false
        }
        guard let selectedTop else { return false }

        pinnedBase = selectedTop
        self.selectedTop = nil
        return true
    }

    mutating func unpin() {
        pinnedBase = nil
    }

    mutating func clearTop() {
        selectedTop = nil
    }

    mutating func remove(where shouldRemove: (Element) -> Bool) {
        if let pinnedBase, shouldRemove(pinnedBase) {
            self.pinnedBase = nil
        }
        if let selectedTop, shouldRemove(selectedTop) {
            self.selectedTop = nil
        }
    }

    mutating func reset() {
        pinnedBase = nil
        selectedTop = nil
    }
}
