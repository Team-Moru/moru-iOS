//
//  RoutineAudioResourceLoader.swift
//  Moru
//

import Foundation

enum RoutineAudioCueKind: String, CaseIterable, Hashable {
  case intro
  case done
  case remind
}

struct RoutineAudioCue: Hashable {
  let itemID: String
  let itemTitle: String
  let voiceName: String
  let voiceCode: String
  let kind: RoutineAudioCueKind
  let relativePath: String
}

enum RoutineAudioResourceError: Error, Equatable {
  case missingResource(String)
  case malformedCSV(row: Int)
  case missingValue(column: String, row: Int)
  case invalidCueKind(String, row: Int)
  case duplicateMapping(itemID: String, voiceCode: String, kind: RoutineAudioCueKind)
  case invalidResourcePath(String)
}

final class RoutineAudioResourceLoader {
  private let resourceDirectory: URL
  private let mappingURL: URL
  private var cachedCues: [RoutineAudioCue]?

  init(resourceDirectory: URL) {
    self.resourceDirectory = resourceDirectory
    mappingURL = resourceDirectory.appendingPathComponent("routine-audio-mapping.csv")
  }

  convenience init(bundle: Bundle = .main) {
    let resourceURL = bundle.resourceURL ?? bundle.bundleURL
    self.init(resourceDirectory: resourceURL)
  }

  func loadCues() throws -> [RoutineAudioCue] {
    if let cachedCues {
      return cachedCues
    }

    guard FileManager.default.fileExists(atPath: mappingURL.path) else {
      throw RoutineAudioResourceError.missingResource("RoutinePresets/routine-audio-mapping.csv")
    }

    let content = try String(contentsOf: mappingURL, encoding: .utf8)
    let rows = try CSVDocument.parse(content)
    guard let header = rows.first else {
      throw RoutineAudioResourceError.malformedCSV(row: 1)
    }

    var keys = Set<MappingKey>()
    let cues: [RoutineAudioCue] = try rows.dropFirst().enumerated().compactMap { offset, values in
      let rowNumber = offset + 2
      guard values.contains(where: { !$0.isEmpty }) else {
        return nil
      }
      guard values.count == header.count else {
        throw RoutineAudioResourceError.malformedCSV(row: rowNumber)
      }

      let row = Dictionary(uniqueKeysWithValues: zip(header, values))
      let itemID = try requiredValue("항목ID", in: row, row: rowNumber)
      let voiceCode = try requiredValue("보이스코드", in: row, row: rowNumber)
      let kindValue = try requiredValue("멘트종류", in: row, row: rowNumber)
      guard let kind = RoutineAudioCueKind(rawValue: kindValue) else {
        throw RoutineAudioResourceError.invalidCueKind(kindValue, row: rowNumber)
      }

      let key = MappingKey(itemID: itemID, voiceCode: voiceCode, kind: kind)
      guard keys.insert(key).inserted else {
        throw RoutineAudioResourceError.duplicateMapping(
          itemID: itemID,
          voiceCode: voiceCode,
          kind: kind
        )
      }

      let relativePath = try requiredValue("파일경로", in: row, row: rowNumber)
      guard resourceURL(for: relativePath) != nil else {
        throw RoutineAudioResourceError.invalidResourcePath(relativePath)
      }

      return RoutineAudioCue(
        itemID: itemID,
        itemTitle: try requiredValue("항목명", in: row, row: rowNumber),
        voiceName: try requiredValue("보이스", in: row, row: rowNumber),
        voiceCode: voiceCode,
        kind: kind,
        relativePath: relativePath
      )
    }
    cachedCues = cues
    return cues
  }

  func cue(
    itemID: String,
    voiceCode: String,
    kind: RoutineAudioCueKind
  ) throws -> RoutineAudioCue? {
    try loadCues().first {
      $0.itemID == itemID && $0.voiceCode == voiceCode && $0.kind == kind
    }
  }

  func resourceURL(for cue: RoutineAudioCue) -> URL? {
    resourceURL(for: cue.relativePath)
  }

  private func resourceURL(for relativePath: String) -> URL? {
    let rootURL = resourceDirectory.standardizedFileURL
    let nestedURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL
    guard nestedURL.path.hasPrefix(rootURL.path + "/") else {
      return nil
    }

    if FileManager.default.fileExists(atPath: nestedURL.path) {
      return nestedURL
    }

    let flattenedURL = rootURL.appendingPathComponent(
      URL(fileURLWithPath: relativePath).lastPathComponent
    )
    return FileManager.default.fileExists(atPath: flattenedURL.path) ? flattenedURL : nil
  }

  private func requiredValue(
    _ column: String,
    in rowValues: [String: String],
    row: Int
  ) throws -> String {
    guard let value = rowValues[column]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
      throw RoutineAudioResourceError.missingValue(column: column, row: row)
    }
    return value
  }
}

private struct MappingKey: Hashable {
  let itemID: String
  let voiceCode: String
  let kind: RoutineAudioCueKind
}
