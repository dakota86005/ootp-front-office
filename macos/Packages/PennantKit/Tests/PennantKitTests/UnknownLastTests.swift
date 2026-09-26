import Foundation
import Testing
@testable import PennantKit

/// The unknown-last comparator on the cases it shares with the TypeScript reference (`tests/sortCases.test.ts`):
/// `contract/fixtures/sort-cases.json`, read where it is.
@Suite("The unknown-last comparator")
struct UnknownLastTests {
    struct SortCase: Sendable, CustomTestStringConvertible {
        let name: String
        let direction: SortDirection
        let rows: [(id: String, key: SortKey?)]
        let expected: [String]
        var testDescription: String { name }
    }

    static func cases() throws -> [SortCase] {
        let object = try JSONSerialization.jsonObject(with: fixtureData("sort-cases.json")) as? [String: Any]
        let cases = try #require(object?["cases"] as? [[String: Any]])
        return try cases.map { item in
            let rows = try #require(item["rows"] as? [[Any]]).map { row -> (id: String, key: SortKey?) in
                let id = row[0] as! String
                switch row[1] {
                case let text as String: return (id, .text(text))
                case let number as NSNumber: return (id, .number(number.doubleValue))
                default: return (id, nil)
                }
            }
            return SortCase(
                name: try #require(item["name"] as? String),
                direction: try #require((item["direction"] as? String).flatMap(SortDirection.init(rawValue:))),
                rows: rows,
                expected: try #require(item["expected"] as? [String])
            )
        }
    }

    @Test("the shared cases", arguments: try cases())
    func shared(_ sortCase: SortCase) {
        let ordered = UnknownLast.sorted(sortCase.rows, by: \.key, direction: sortCase.direction).map(\.id)
        #expect(ordered == sortCase.expected)
    }

    @Test("there are shared cases, with unknown keys in both directions")
    func coverage() throws {
        let cases = try Self.cases()
        #expect(cases.count >= 10)
        for direction in [SortDirection.ascending, .descending] {
            #expect(cases.contains { $0.direction == direction && $0.rows.contains { $0.key == nil } })
        }
    }

    @Test("unknown never precedes, and every known key precedes unknown, both ways")
    func unknownIsLast() {
        for direction in [SortDirection.ascending, .descending] {
            #expect(UnknownLast.precedes(nil, .number(-1_000), direction: direction) == false)
            #expect(UnknownLast.precedes(.number(-1_000), nil, direction: direction))
            #expect(UnknownLast.precedes(.text(""), nil, direction: direction))
            #expect(UnknownLast.precedes(nil, nil, direction: direction) == false)
        }
    }
}
