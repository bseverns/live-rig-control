import Foundation
import MappingValidator

private func repoRootUrl() -> URL {
    URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func loadMapping(at url: URL) throws -> Mapping {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Mapping.self, from: data)
}

private func loadMapping(json: String) throws -> Mapping {
    try JSONDecoder().decode(Mapping.self, from: Data(json.utf8))
}

#if canImport(Testing)
import Testing

@Test
func mappingsJsonValid() throws {
    let mappingsPath = repoRootUrl()
        .appendingPathComponent("src")
        .appendingPathComponent("mappings.json")
    let mapping = try loadMapping(at: mappingsPath)
    let result = MappingValidator().validate(mapping)

    #expect(result.errors.isEmpty, "mappings.json errors:\n\(result.errors.joined(separator: "\n"))")
    #expect(result.warnings.isEmpty, "mappings.json warnings:\n\(result.warnings.joined(separator: "\n"))")
}

@Test
func mappingsFixtureValid() throws {
    let fixturePath = repoRootUrl()
        .appendingPathComponent("ios")
        .appendingPathComponent("Tests")
        .appendingPathComponent("fixtures")
        .appendingPathComponent("mappings.json")
    let mapping = try loadMapping(at: fixturePath)
    let result = MappingValidator().validate(mapping)

    #expect(result.errors.isEmpty, "fixture errors:\n\(result.errors.joined(separator: "\n"))")
    #expect(result.warnings.isEmpty, "fixture warnings:\n\(result.warnings.joined(separator: "\n"))")
}

@Test
func rejectsGlobalDuplicatePadIds() throws {
    let mapping = try loadMapping(json: #"{"profiles":{"a":{"gridSize":[1,1],"pads":[{"id":"duplicate","ui":{"type":"button"}}]},"b":{"gridSize":[1,1],"pads":[{"id":"duplicate","ui":{"type":"button"}}]}}}"#)
    let result = MappingValidator().validate(mapping)
    #expect(result.errors.contains(where: { $0.contains("duplicate pad id across profiles") }))
}

@Test
func enforcesMidiFieldsAndChannelSemantics() throws {
    let invalid = try loadMapping(json: #"{"profiles":{"test":{"gridSize":[2,1],"pads":[{"id":"note","midi":{"type":"note"}},{"id":"cc","midi":{"type":"cc","channel":1}}]}}}"#)
    let errors = MappingValidator().validate(invalid).errors
    #expect(errors.contains(where: { $0.contains("midi.channel missing") }))
    #expect(errors.contains(where: { $0.contains("midi.note missing") }))
    #expect(errors.contains(where: { $0.contains("midi.cc missing") }))

    let realtime = try loadMapping(json: #"{"profiles":{"test":{"gridSize":[1,1],"pads":[{"id":"start","midi":{"type":"realtime","realtime":"start"}}]}}}"#)
    #expect(MappingValidator().validate(realtime).errors.isEmpty)

    let channeledRealtime = try loadMapping(json: #"{"profiles":{"test":{"gridSize":[1,1],"pads":[{"id":"start","midi":{"type":"realtime","channel":1,"realtime":"start"}}]}}}"#)
    #expect(MappingValidator().validate(channeledRealtime).errors.contains(where: { $0.contains("must be omitted") }))
}

@Test
func rejectsEmptyOscAddressAndNullArgs() throws {
    let emptyAddress = try loadMapping(json: #"{"profiles":{"test":{"gridSize":[1,1],"pads":[{"id":"osc","osc":{"address":"   ","args":[]}}]}}}"#)
    #expect(MappingValidator().validate(emptyAddress).errors.contains(where: { $0.contains("osc.address") }))

    #expect(throws: DecodingError.self) {
        _ = try loadMapping(json: #"{"profiles":{"test":{"gridSize":[1,1],"pads":[{"id":"osc","osc":{"address":"/ok","args":[null]}}]}}}"#)
    }
}

#elseif canImport(XCTest)
import XCTest

final class MappingValidatorTests: XCTestCase {
    func testMappingsJsonValid() throws {
        let mappingsPath = repoRootUrl()
            .appendingPathComponent("src")
            .appendingPathComponent("mappings.json")
        let mapping = try loadMapping(at: mappingsPath)
        let result = MappingValidator().validate(mapping)

        if !result.errors.isEmpty {
            XCTFail("mappings.json errors:\n" + result.errors.joined(separator: "\n"))
        }
        if !result.warnings.isEmpty {
            XCTFail("mappings.json warnings:\n" + result.warnings.joined(separator: "\n"))
        }
    }

    func testMappingsFixtureValid() throws {
        let fixturePath = repoRootUrl()
            .appendingPathComponent("ios")
            .appendingPathComponent("Tests")
            .appendingPathComponent("fixtures")
            .appendingPathComponent("mappings.json")
        let mapping = try loadMapping(at: fixturePath)
        let result = MappingValidator().validate(mapping)

        if !result.errors.isEmpty {
            XCTFail("fixture errors:\n" + result.errors.joined(separator: "\n"))
        }
        if !result.warnings.isEmpty {
            XCTFail("fixture warnings:\n" + result.warnings.joined(separator: "\n"))
        }
    }

    func testRejectsGlobalDuplicatePadIds() throws {
        let mapping = try loadMapping(json: #"{"profiles":{"a":{"gridSize":[1,1],"pads":[{"id":"duplicate","ui":{"type":"button"}}]},"b":{"gridSize":[1,1],"pads":[{"id":"duplicate","ui":{"type":"button"}}]}}}"#)
        let errors = MappingValidator().validate(mapping).errors
        XCTAssertTrue(errors.contains(where: { $0.contains("duplicate pad id across profiles") }))
    }

    func testEnforcesMidiFieldsAndChannelSemantics() throws {
        let invalid = try loadMapping(json: #"{"profiles":{"test":{"gridSize":[2,1],"pads":[{"id":"note","midi":{"type":"note"}},{"id":"cc","midi":{"type":"cc","channel":1}}]}}}"#)
        let errors = MappingValidator().validate(invalid).errors
        XCTAssertTrue(errors.contains(where: { $0.contains("midi.channel missing") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("midi.note missing") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("midi.cc missing") }))

        let realtime = try loadMapping(json: #"{"profiles":{"test":{"gridSize":[1,1],"pads":[{"id":"start","midi":{"type":"realtime","realtime":"start"}}]}}}"#)
        XCTAssertTrue(MappingValidator().validate(realtime).errors.isEmpty)

        let channeledRealtime = try loadMapping(json: #"{"profiles":{"test":{"gridSize":[1,1],"pads":[{"id":"start","midi":{"type":"realtime","channel":1,"realtime":"start"}}]}}}"#)
        XCTAssertTrue(MappingValidator().validate(channeledRealtime).errors.contains(where: { $0.contains("must be omitted") }))
    }

    func testRejectsEmptyOscAddressAndNullArgs() throws {
        let emptyAddress = try loadMapping(json: #"{"profiles":{"test":{"gridSize":[1,1],"pads":[{"id":"osc","osc":{"address":"   ","args":[]}}]}}}"#)
        XCTAssertTrue(MappingValidator().validate(emptyAddress).errors.contains(where: { $0.contains("osc.address") }))

        XCTAssertThrowsError(try loadMapping(json: #"{"profiles":{"test":{"gridSize":[1,1],"pads":[{"id":"osc","osc":{"address":"/ok","args":[null]}}]}}}"#))
    }
}
#else
#error("No Testing or XCTest module available. Use Xcode toolchain or install swift-testing.")
#endif
