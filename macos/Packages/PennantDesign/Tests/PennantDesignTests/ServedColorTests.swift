import Testing
@testable import PennantDesign

@Suite("Served colours")
struct ServedColorTests {
    @Test("a served hex colour reads as its sRGB components")
    func reads() throws {
        let navy = try #require(ServedColor.components("#1d2d44"))
        #expect(navy.red == 0x1d / 255.0 && navy.green == 0x2d / 255.0 && navy.blue == 0x44 / 255.0)
        let short = try #require(ServedColor.components("fff"))
        #expect(short.red == 1 && short.green == 1 && short.blue == 1)
    }

    @Test("anything that is not a colour reads as nil, never as black")
    func rejects() {
        for text in [nil, "", "#", "#12345", "#gggggg", "navy", "#1d2d44ff"] as [String?] {
            #expect(ServedColor.components(text) == nil)
        }
    }
}
