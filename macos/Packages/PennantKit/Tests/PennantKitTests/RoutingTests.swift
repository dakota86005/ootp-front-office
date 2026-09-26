import Foundation
import Testing
@testable import PennantKit

/// Routes and references are saved per window and carried by drags, so each survives an encode and decode as
/// itself, and a department saved by a newer build still reads.
@Suite("Routes and references")
struct RoutingTests {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    @Test("a route round-trips")
    func route() throws {
        let route = AppRoute(department: "majorLeague", view: "positionPlayers")
        #expect(try roundTrip(route) == route)
        let json = try #require(String(data: JSONEncoder().encode(route), encoding: .utf8))
        #expect(json.contains(#""department":"majorLeague""#))
    }

    @Test("a department this build does not know still decodes")
    func unknownDepartment() throws {
        let route = try JSONDecoder().decode(AppRoute.self, from: Data(#"{"department":"analytics","view":"report"}"#.utf8))
        #expect(route.department.rawValue == "analytics")
        #expect(route.view == "report")
    }

    @Test("player, club and comparison references round-trip")
    func references() throws {
        #expect(try roundTrip(PlayerRef(id: 31)) == PlayerRef(id: 31))
        #expect(try roundTrip(ClubRef(id: 1)) == ClubRef(id: 1))
        let comparison = ComparisonRef(players: [PlayerRef(id: 10), PlayerRef(id: 60)], clubs: [ClubRef(id: 3)])
        #expect(try roundTrip(comparison) == comparison)
        #expect(try roundTrip(ComparisonRef()) == ComparisonRef())
    }

    @Test("references hash by value, so a window opened twice for one player is one window")
    func hashing() {
        #expect(Set([PlayerRef(id: 10), PlayerRef(id: 10), PlayerRef(id: 11)]).count == 2)
        #expect(Set([AppRoute(department: "farm", view: "report"), AppRoute(department: "farm", view: "report")]).count == 1)
    }
}
