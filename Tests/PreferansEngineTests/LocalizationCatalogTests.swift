import Foundation
import XCTest

final class LocalizationCatalogTests: XCTestCase {
    private let supportedLanguages = ["en", "ru", "uk"]

    func testStringCatalogIsCompleteForSupportedLanguages() throws {
        let strings = try catalogStrings()

        var failures: [String] = []
        for key in strings.keys.sorted() {
            guard let entry = strings[key] as? [String: Any] else {
                failures.append("\"\(key)\" has a malformed catalog entry.")
                continue
            }
            guard let localizations = entry["localizations"] as? [String: Any] else {
                failures.append("\"\(key)\" has no localizations.")
                continue
            }

            for language in supportedLanguages {
                guard let localization = localizations[language] as? [String: Any] else {
                    failures.append("\"\(key)\" is missing \(language).")
                    continue
                }

                let units = stringUnits(in: localization)
                if units.isEmpty {
                    failures.append("\"\(key)\" \(language) has no stringUnit leaves.")
                    continue
                }

                for unit in units {
                    if unit.state != "translated" {
                        failures.append("\"\(key)\" \(language) \(unit.path) is \(unit.state), expected translated.")
                    }
                    if unit.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        failures.append("\"\(key)\" \(language) \(unit.path) has an empty value.")
                    }
                }
            }
        }

        if !failures.isEmpty {
            let shown = failures.prefix(60).joined(separator: "\n")
            let suffix = failures.count > 60 ? "\n...and \(failures.count - 60) more." : ""
            XCTFail("String catalog localization audit failed:\n\(shown)\(suffix)")
        }
    }

    func testDiagnosticErrorsAreNotLocalized() throws {
        let strings = try catalogStrings()
        let forbiddenKeys = [
            "Invalid state. Expected %@, got %@.",
            "Game Center error: %@",
            "CloudKit table save failed: %@",
            "CloudKit archive failed: %@"
        ]

        for key in forbiddenKeys {
            XCTAssertNil(strings[key], "Diagnostic error strings should stay raw, not catalog-localized.")
        }
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private struct StringUnit {
        var path: String
        var state: String
        var value: String
    }

    private func catalogStrings() throws -> [String: Any] {
        let catalogURL = projectRoot
            .appending(path: "Preferans")
            .appending(path: "Resources")
            .appending(path: "Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "Localizable.xcstrings should be a JSON object."
        )
        return try XCTUnwrap(
            root["strings"] as? [String: Any],
            "Localizable.xcstrings should contain a top-level strings object."
        )
    }

    private func stringUnits(in value: Any, path: String = "") -> [StringUnit] {
        if let dictionary = value as? [String: Any] {
            var units: [StringUnit] = []
            if let stringUnit = dictionary["stringUnit"] as? [String: Any] {
                units.append(
                    StringUnit(
                        path: path.isEmpty ? "stringUnit" : "\(path).stringUnit",
                        state: stringUnit["state"] as? String ?? "<missing>",
                        value: stringUnit["value"] as? String ?? ""
                    )
                )
            }

            for key in dictionary.keys.sorted() where key != "stringUnit" {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                units.append(contentsOf: stringUnits(in: dictionary[key] as Any, path: childPath))
            }
            return units
        }

        if let array = value as? [Any] {
            return array.enumerated().flatMap { index, element in
                stringUnits(in: element, path: "\(path)[\(index)]")
            }
        }

        return []
    }
}
