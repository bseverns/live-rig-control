import Foundation

func usage() {
    print("Usage: MappingValidator --mappings <path>")
    print("Defaults: --mappings ../src/mappings.json")
}

func parseArgs(_ args: [String]) -> (String, Bool) {
    var path = "../src/mappings.json"
    var showHelp = false
    var idx = 0
    while idx < args.count {
        switch args[idx] {
        case "--mappings", "-m":
            if idx + 1 < args.count {
                path = args[idx + 1]
                idx += 1
            }
        case "--help", "-h":
            showHelp = true
        default:
            break
        }
        idx += 1
    }
    return (path, showHelp)
}

let (pathArg, showHelp) = parseArgs(Array(CommandLine.arguments.dropFirst()))
if showHelp {
    usage()
    exit(0)
}

let url = URL(fileURLWithPath: pathArg)
do {
    let data = try Data(contentsOf: url)
    let mapping = try JSONDecoder().decode(Mapping.self, from: data)
    let result = MappingValidator().validate(mapping)

    if result.errors.isEmpty && result.warnings.isEmpty {
        print("mappings.json validation OK.")
        exit(0)
    }

    if !result.errors.isEmpty {
        print("Errors:")
        for error in result.errors {
            print("  - \(error)")
        }
    }
    if !result.warnings.isEmpty {
        print("Warnings:")
        for warning in result.warnings {
            print("  - \(warning)")
        }
    }
    exit(result.errors.isEmpty ? 0 : 1)
} catch {
    print("Failed to validate mappings: \(error.localizedDescription)")
    exit(1)
}
