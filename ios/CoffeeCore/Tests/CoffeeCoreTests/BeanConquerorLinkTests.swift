import Foundation
import Testing

@testable import CoffeeCore

@Suite struct BeanConquerorLinkTests {
    private let chicago = TimeZone(identifier: "America/Chicago")!

    private var finalFrontier: BagDraft {
        var draft = BagDraft()
        draft.coffee = "Final Frontier"
        draft.roaster = "Proud Mary Coffee USA"
        draft.roastDate = "2026-10-12"
        draft.weightGrams = 250
        draft.notes = "Apple, Blackberries, Plum"
        draft.url = "https://proudmarycoffee.com/products/honduras"
        draft.country = "Honduras"
        draft.region = "Santa Barbara"
        draft.producer = "Nahun Fernandez"
        draft.variety = "Parainema"
        draft.process = "Natural"
        return draft
    }

    /// The shareUserBean parameters joined and decoded back to bytes.
    private func bytes(of url: URL?) -> [UInt8]? {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let code = items.filter { $0.name.hasPrefix("shareUserBean") }.compactMap(\.value).joined()
        return Data(base64Encoded: code).map { Array($0) }
    }

    @Test func encodesABagAsBeanConquerorDoes() {
        // Made by a separate encoder, whose link BeanConqueror read with the
        // weight and the roast date right
        let expected =
            "Cg5GaW5hbCBGcm9udGllchoYMjAyNi0xMC0xMlQwNTowMDowMC4wMDBaKhVQcm91ZCBNYXJ5IENvZmZlZSBVU0FaGUFwcGxlLCBCbGFja2Jlcn"
            + "JpZXMsIFBsdW1g+gGSAS1odHRwczovL3Byb3VkbWFyeWNvZmZlZS5jb20vcHJvZHVjdHMvaG9uZHVyYXNIAaoBPgoISG9uZHVyYXMSDVNhbnRh"
            + "IEJhcmJhcmEiD05haHVuIEZlcm5hbmRlejoJUGFyYWluZW1hQgdOYXR1cmFs"
        let url = BeanConquerorLink.url(for: finalFrontier, timeZone: chicago)
        #expect(url?.absoluteString.hasPrefix("beanconqueror://ADD_USER_BEAN?shareUserBean0=") == true)
        #expect(bytes(of: url) == Array(Data(base64Encoded: expected)!))
    }

    @Test func percentEncodesTheBase64() {
        let url = BeanConquerorLink.url(for: finalFrontier, timeZone: chicago)?.absoluteString ?? ""
        #expect(url.contains("%2B"))  // The weight's "+" isn't read as a space
        #expect(!url.contains("+"))
    }

    @Test func splitsALongBagInto400CharacterParameters() throws {
        var draft = finalFrontier
        draft.notes = String(repeating: "Blackcurrant, ", count: 20)
        let url = try #require(BeanConquerorLink.url(for: draft, timeZone: chicago))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.map(\.name) == ["shareUserBean0", "shareUserBean1"])
        #expect(items[0].value?.count == 400)
        #expect(bytes(of: url) == BeanConquerorLink.encode(draft, timeZone: chicago))
    }

    @Test func needsACoffee() {
        var draft = finalFrontier
        draft.coffee = "  "
        #expect(BeanConquerorLink.url(for: draft, timeZone: chicago) == nil)
    }

    @Test func leavesOutEmptyFieldsAndTheOriginWithNothingInIt() {
        var draft = BagDraft()
        draft.coffee = "Putushio"
        // Field 1, length 8, "Putushio"
        #expect(BeanConquerorLink.encode(draft, timeZone: chicago) == [0x0A, 8] + Array("Putushio".utf8))
    }

    @Test func theRoastDateIsMidnightWhereThePhoneIs() {
        #expect(BeanConquerorLink.instant(of: "2026-10-12", in: chicago) == "2026-10-12T05:00:00.000Z")
        #expect(BeanConquerorLink.instant(of: "2026-01-12", in: chicago) == "2026-01-12T06:00:00.000Z")
        #expect(BeanConquerorLink.instant(of: "2026-10-12", in: TimeZone(identifier: "Asia/Tokyo")!) == "2026-10-11T15:00:00.000Z")
        #expect(BeanConquerorLink.instant(of: "2026-13-40", in: chicago) == nil)
    }
}
