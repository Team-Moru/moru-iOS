//
//  MoruAlarmMetadata.swift
//  Moru
//
//  Created by 김승겸 on 7/12/26.
//

import AlarmKit

struct MoruAlarmMetadata: AlarmMetadata {
  let ingress: AlarmIngressEnvelope
  let routineName: String
}
