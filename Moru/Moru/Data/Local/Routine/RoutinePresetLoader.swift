//
//  RoutinePresetLoader.swift
//  Moru
//

import Foundation

enum RoutinePresetLoaderError: Error, Equatable {
  case missingResource(String)
  case malformedCSV(row: Int)
  case missingValue(column: String, row: Int)
  case invalidStepType(String, row: Int)
  case invalidEstimatedSeconds(String, row: Int)
  case duplicateItemID(String)
}

struct RoutinePresetLoader: RoutinePresetProviding {
  private let fileURL: URL

  init(resourceDirectory: URL) {
    fileURL = resourceDirectory.appendingPathComponent("recommended-items.csv")
  }

  init(bundle: Bundle = .main) {
    let resourceURL = bundle.resourceURL ?? bundle.bundleURL
    self.init(resourceDirectory: resourceURL)
  }

  func loadItems() throws -> [RoutinePresetItem] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw RoutinePresetLoaderError.missingResource("RoutinePresets/recommended-items.csv")
    }

    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let rows: [[String]]

    do {
      rows = try CSVDocument.parse(content)
    } catch let CSVDocumentError.unterminatedQuote(row) {
      throw RoutinePresetLoaderError.malformedCSV(row: row)
    }

    guard let header = rows.first else {
      throw RoutinePresetLoaderError.malformedCSV(row: 1)
    }
    guard Set(header).count == header.count else {
      throw RoutinePresetLoaderError.malformedCSV(row: 1)
    }

    var itemIDs = Set<String>()
    return try rows.dropFirst().enumerated().compactMap { offset, values in
      let rowNumber = offset + 2
      guard values.contains(where: { !$0.isEmpty }) else {
        return nil
      }
      guard values.count == header.count else {
        throw RoutinePresetLoaderError.malformedCSV(row: rowNumber)
      }

      let row = Dictionary(uniqueKeysWithValues: zip(header, values))
      let itemID = try requiredValue("항목ID", in: row, row: rowNumber)
      guard itemIDs.insert(itemID).inserted else {
        throw RoutinePresetLoaderError.duplicateItemID(itemID)
      }

      let typeCode = try requiredValue("유형코드", in: row, row: rowNumber)
      guard let type = stepType(for: typeCode) else {
        throw RoutinePresetLoaderError.invalidStepType(typeCode, row: rowNumber)
      }

      let secondsValue = try requiredValue("시간(초)", in: row, row: rowNumber)
      guard let estimatedSeconds = Int(secondsValue), estimatedSeconds > 0 else {
        throw RoutinePresetLoaderError.invalidEstimatedSeconds(secondsValue, row: rowNumber)
      }

      return RoutinePresetItem(
        id: itemID,
        goal: try requiredValue("목표", in: row, row: rowNumber),
        title: try requiredValue("항목명", in: row, row: rowNumber),
        type: type,
        estimatedSeconds: estimatedSeconds,
        isCommon: row["공통항목"] == "Y"
      )
    }
  }

  private func requiredValue(
    _ column: String,
    in rowValues: [String: String],
    row: Int
  ) throws -> String {
    guard let value = rowValues[column]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
      throw RoutinePresetLoaderError.missingValue(column: column, row: row)
    }
    return value
  }

  private func stepType(for code: String) -> RoutineStepType? {
    switch code {
    case "CONFIRM": .confirm
    case "TIMER": .timer
    case "INPUT": .input
    default: nil
    }
  }
}

enum CSVDocumentError: Error, Equatable {
  case unterminatedQuote(row: Int)
}

enum CSVDocument {
  static func parse(_ content: String) throws -> [[String]] {
    let normalizedContent = content
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var isQuoted = false
    var index = normalizedContent.startIndex

    while index < normalizedContent.endIndex {
      let character = normalizedContent[index]
      let nextIndex = normalizedContent.index(after: index)

      if character == "\"" {
        if isQuoted, nextIndex < normalizedContent.endIndex, normalizedContent[nextIndex] == "\"" {
          field.append("\"")
          index = normalizedContent.index(after: nextIndex)
          continue
        }
        isQuoted.toggle()
      } else if character == ",", !isQuoted {
        row.append(field)
        field = ""
      } else if (character == "\n" || character == "\r"), !isQuoted {
        index = nextIndex
        row.append(field)
        rows.append(row)
        row = []
        field = ""
        continue
      } else {
        field.append(character)
      }

      index = nextIndex
    }

    guard !isQuoted else {
      throw CSVDocumentError.unterminatedQuote(row: rows.count + 1)
    }

    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      rows.append(row)
    }

    if let first = rows.first?.first {
      rows[0][0] = first.replacingOccurrences(of: "\u{FEFF}", with: "")
    }
    return rows
  }
}

extension LocalTemplateSuggestionService {
  static let shared = LocalTemplateSuggestionService(presetProvider: RoutinePresetLoader())
}
