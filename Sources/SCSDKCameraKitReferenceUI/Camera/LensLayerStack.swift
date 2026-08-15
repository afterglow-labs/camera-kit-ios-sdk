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
    mutating func pinCurrent() -> Bool {
        guard pinnedBase == nil, let selectedTop else { return false }

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

struct LensLayerIdentity: Equatable {
    let id: String
    let groupID: String
}

enum LensLayerDisplay {
    static func name(base: String?, top: String?) -> String {
        switch (base, top) {
        case let (base?, top?):
            return "\(base) + \(top)"
        case let (base?, nil):
            return "\(base) (Pinned)"
        case let (nil, top?):
            return top
        case (nil, nil):
            return ""
        }
    }
}
