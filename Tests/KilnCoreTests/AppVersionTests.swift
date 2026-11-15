import Foundation
import Testing
@testable import KilnCore

@Suite struct AppVersionTests {
    @Test func parsesDottedNumbersWithOrWithoutALeadingV() {
        #expect(AppVersion("0.2.0")?.description == "0.2.0")
        #expect(AppVersion("v0.2.0")?.description == "0.2.0")
        #expect(AppVersion("V1.4")?.description == "1.4")
        #expect(AppVersion(" v3 \n")?.description == "3")
    }

    @Test(arguments: [
        "", "v", "latest", "1..2", ".1", "1.", "1.2-beta", "1.2.0-rc.1", "1.2b", "vv1", "1,2", "-1.0", "+1.0",
        "1. 2", "١.٢", "1.2.3.4.5.6.7.8.9", "1.99999999999999999999",
    ])
    func rejectsAnythingElse(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func comparesNumberByNumber() throws {
        let old = try #require(AppVersion("0.9.2"))
        let new = try #require(AppVersion("0.10.0"))
        let major = try #require(AppVersion("1.0"))
        #expect(old < new)
        #expect(new > old)
        #expect(major > new)
        #expect(AppVersion("0.1.1")! > AppVersion("0.1")!)
        #expect(AppVersion("2")! < AppVersion("2.0.1")!)
        #expect(AppVersion("007")! == AppVersion("7")!)
    }

    @Test func missingComponentsCountAsZero() throws {
        let short = try #require(AppVersion("0.1"))
        let long = try #require(AppVersion("v0.1.0"))
        #expect(short == long)
        #expect(!(short < long))
        #expect(!(long < short))
        #expect(Set([short, long]).count == 1)
    }
}
