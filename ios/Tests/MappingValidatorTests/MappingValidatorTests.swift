import Foundation
import MappingValidator

#if canImport(Testing)
import Testing

@Test
func mappingsJsonValid() throws {
    let mappingsPath = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("src")
        .appendingPathComponent("mappings.json")

    let data = try Data(contentsOf: mappingsPath)
    let mapping = try JSONDecoder().decode(Mapping.self, from: data)
    let result = MappingValidator().validate(mapping)

    #expect(result.errors.isEmpty, "mappings.json errors:\n\(result.errors.joined(separator: "\n"))")
    #expect(result.warnings.isEmpty, "mappings.json warnings:\n\(result.warnings.joined(separator: "\n"))")
}

#elseif canImport(XCTest)
import XCTest

final class MappingValidatorTests: XCTestCase {
    func testMappingsJsonValid() throws {
        let mappingsPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src")
            .appendingPathComponent("mappings.json")

        let data = try Data(contentsOf: mappingsPath)
        let mapping = try JSONDecoder().decode(Mapping.self, from: data)
        let result = MappingValidator().validate(mapping)

        if !result.errors.isEmpty {
            XCTFail("mappings.json errors:\n" + result.errors.joined(separator: "\n"))
        }
        if !result.warnings.isEmpty {
            XCTFail("mappings.json warnings:\n" + result.warnings.joined(separator: "\n"))
        }
    }
}
#else
#error("No Testing or XCTest module available. Use Xcode toolchain or install swift-testing.")
#endif
