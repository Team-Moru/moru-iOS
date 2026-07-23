//
//  SpeechTranscriptAccumulator.swift
//  Moru
//

import Foundation

struct SpeechTranscriptAccumulator {
  private(set) var finalizedTranscript = ""
  private(set) var volatileTranscript = ""

  var transcript: String {
    (finalizedTranscript + volatileTranscript)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  mutating func append(_ text: String, isFinal: Bool) -> String {
    if isFinal {
      finalizedTranscript += text
      volatileTranscript = ""
    } else {
      volatileTranscript = text
    }

    return transcript
  }
}
