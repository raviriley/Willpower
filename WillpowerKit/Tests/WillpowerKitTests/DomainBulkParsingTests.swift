//
//  DomainBulkParsingTests.swift
//  WillpowerKitTests
//

import Testing
@testable import WillpowerKit

@Suite("Bulk domain parsing")
struct DomainBulkParsingTests {

    @Test("Empty and whitespace-only text yields nothing")
    func emptyText() {
        #expect(DomainBulkParsing.parseDomains(fromPastedText: "") == [])
        #expect(DomainBulkParsing.parseDomains(fromPastedText: "   \n\n \t ") == [])
    }

    @Test("One domain per line")
    func onePerLine() {
        let result = DomainBulkParsing.parseDomains(fromPastedText: "reuters.com\napnews.com\nbbc.com")
        #expect(result == ["reuters.com", "apnews.com", "bbc.com"])
    }

    @Test("Comma separated")
    func commaSeparated() {
        let result = DomainBulkParsing.parseDomains(fromPastedText: "reuters.com, apnews.com, bbc.com")
        #expect(result == ["reuters.com", "apnews.com", "bbc.com"])
    }

    @Test("Semicolons, tabs and spaces all separate")
    func otherSeparators() {
        #expect(DomainBulkParsing.parseDomains(fromPastedText: "a.com;b.com\tc.com d.com")
                == ["a.com", "b.com", "c.com", "d.com"])
    }

    @Test("Mixed separators and blank lines")
    func messyInput() {
        let messy = "reuters.com, apnews.com\n\n  bbc.com  \n\nnpr.org\n"
        #expect(DomainBulkParsing.parseDomains(fromPastedText: messy)
                == ["reuters.com", "apnews.com", "bbc.com", "npr.org"])
    }

    @Test("Full URLs reduce to hostnames")
    func fullURLs() {
        let urls = "https://www.reuters.com/world/europe\nhttp://apnews.com/hub/politics?x=1"
        #expect(DomainBulkParsing.parseDomains(fromPastedText: urls) == ["reuters.com", "apnews.com"])
    }

    @Test("Comments are stripped")
    func comments() {
        let text = "# my list\nreuters.com\n# another\nbbc.com # trailing\n"
        #expect(DomainBulkParsing.parseDomains(fromPastedText: text) == ["reuters.com", "bbc.com"])
    }

    @Test("Hosts-file lines drop the redirect target")
    func hostsFile() {
        let hosts = "0.0.0.0 reddit.com\n127.0.0.1 x.com\n::1 instagram.com\n"
        #expect(DomainBulkParsing.parseDomains(fromPastedText: hosts)
                == ["reddit.com", "x.com", "instagram.com"])
    }

    @Test("Hosts-file line with several hostnames keeps them all")
    func hostsFileMultiple() {
        #expect(DomainBulkParsing.parseDomains(fromPastedText: "0.0.0.0 reddit.com www.reddit.com")
                == ["reddit.com"])
    }

    @Test("Duplicates are removed, first occurrence wins")
    func duplicates() {
        #expect(DomainBulkParsing.parseDomains(fromPastedText: "bbc.com\nBBC.com\nnpr.org\nbbc.com")
                == ["bbc.com", "npr.org"])
    }

    @Test("Entries that could never be typed in are rejected")
    func invalidEntriesRejected() {
        // no dot, leading/trailing dot, and invalid characters
        #expect(DomainBulkParsing.parseDomains(fromPastedText: "localhost\n.com\nexample.\nbad_domain!.com\nok.com")
                == ["ok.com"])
    }

    @Test("A bare IP on its own line is not treated as a hosts redirect")
    func bareIPAlone() {
        // it has no second field, so nothing is dropped; it fails domain validation
        #expect(DomainBulkParsing.parseDomains(fromPastedText: "93.184.216.34") == ["93.184.216.34"])
    }

    @Test("Export round-trips through parse")
    func exportRoundTrip() {
        let domains = ["reuters.com", "bbc.com", "npr.org"]
        let text = DomainBulkParsing.exportText(for: domains)
        #expect(text == "reuters.com\nbbc.com\nnpr.org\n")
        #expect(DomainBulkParsing.parseDomains(fromPastedText: text) == domains)
    }

    @Test("IP detection")
    func ipDetection() {
        #expect(DomainBulkParsing.isIPAddress("0.0.0.0"))
        #expect(DomainBulkParsing.isIPAddress("127.0.0.1"))
        #expect(DomainBulkParsing.isIPAddress("::1"))
        #expect(!DomainBulkParsing.isIPAddress("reddit.com"))
    }
}
