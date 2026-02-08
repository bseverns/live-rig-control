import Foundation
import XCTest

final class MappingValidatorAppTests: XCTestCase {
    func testFixtureMappingsValid() throws {
        let bundle = Bundle(for: MappingValidatorAppTests.self)
        guard let url = bundle.url(forResource: "mappings", withExtension: "json") else {
            XCTFail("Missing fixture mappings.json in test bundle")
            return
        }

        let data = try Data(contentsOf: url)
        let mapping = try JSONDecoder().decode(Mapping.self, from: data)
        let result = MappingValidator().validate(mapping)

        if !result.errors.isEmpty {
            XCTFail("fixture errors:\n" + result.errors.joined(separator: "\n"))
        }
        if !result.warnings.isEmpty {
            XCTFail("fixture warnings:\n" + result.warnings.joined(separator: "\n"))
        }
    }
}
