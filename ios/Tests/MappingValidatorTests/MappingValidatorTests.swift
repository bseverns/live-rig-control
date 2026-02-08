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
}
#else
#error("No Testing or XCTest module available. Use Xcode toolchain or install swift-testing.")
#endif
