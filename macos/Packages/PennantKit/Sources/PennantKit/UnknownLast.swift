/// A served sort key: a number or a string, or nil when the server does not know (D-056: "null is unknown and
/// sorts last in both directions"). This is the comparator's input, not a server type: a table converts its
/// generated cell's key into it.
public enum SortKey: Sendable, Hashable {
    case number(Double)
    case text(String)
}

public enum SortDirection: String, Sendable, Codable, Hashable {
    case ascending
    case descending
}

/// The unknown-last comparator, the one piece of ordering the app owns (D-056). The rules, shared with the
/// TypeScript reference through `contract/fixtures/sort-cases.json`:
/// - an unknown key (nil) sorts after every known key, whichever the direction;
/// - numbers compare by value, strings by UTF-16 code units (as JavaScript compares them), and every number
///   sorts before every string (reversed when descending, like any known key);
/// - equal keys, and unknown keys among themselves, keep the order the server sent (the sort is stable).
public enum UnknownLast {
    /// Whether `a` sorts strictly before `b`.
    public static func precedes(_ a: SortKey?, _ b: SortKey?, direction: SortDirection) -> Bool {
        switch (a, b) {
        case (nil, _): return false
        case (_?, nil): return true
        case (let a?, let b?):
            return direction == .ascending ? less(a, b) : less(b, a)
        }
    }

    private static func less(_ a: SortKey, _ b: SortKey) -> Bool {
        switch (a, b) {
        case (.number(let x), .number(let y)): return x < y
        case (.number, .text): return true
        case (.text, .number): return false
        case (.text(let x), .text(let y)): return x.utf16.lexicographicallyPrecedes(y.utf16)
        }
    }

    /// The items in order by their key, stable: ties keep the order they came in.
    public static func sorted<Item>(_ items: some Sequence<Item>, by key: (Item) -> SortKey?, direction: SortDirection) -> [Item] {
        items.enumerated()
            .map { (offset: $0.offset, item: $0.element, key: key($0.element)) }
            .sorted { lhs, rhs in
                if precedes(lhs.key, rhs.key, direction: direction) { return true }
                if precedes(rhs.key, lhs.key, direction: direction) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.item)
    }
}
