import PennantAPI

/// The club the app is about: the one chosen in Settings, else the one the save's human manages (AGENTS.md:
/// "resolve the configured organization, then the human-managed OOTP organization"). Everything shown comes from
/// the server's club list (`/api/orgs`).
public struct CurrentClub: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        /// `defaultOrgId` in the server's settings.
        case configured
        /// The club the save's human manages (`isHuman`).
        case humanManaged
    }

    public var ref: ClubRef
    public var org: Components.Schemas.Org
    public var source: Source

    public init(ref: ClubRef, org: Components.Schemas.Org, source: Source) {
        self.ref = ref
        self.org = org
        self.source = source
    }

    /// The configured club when the club list has it, else the human-managed one, else none.
    public static func resolve(configuredID: Int?, orgs: [Components.Schemas.Org]) -> CurrentClub? {
        if let configuredID, configuredID > 0, let org = orgs.first(where: { $0.teamId == configuredID }) {
            return CurrentClub(ref: ClubRef(id: org.teamId), org: org, source: .configured)
        }
        if let org = orgs.first(where: \.isHuman) {
            return CurrentClub(ref: ClubRef(id: org.teamId), org: org, source: .humanManaged)
        }
        return nil
    }
}
