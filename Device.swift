//
//  Device.swift
//  meltixswift
//
//  Created by Tomasz Sadowy on 6/13/25.
//

import Foundation


import Foundation

struct Device: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let type: String
    let lanName: String
    let online: Bool
    
    // Equatable ⇒ compare by primary key
    static func == (lhs: Device, rhs: Device) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.type == rhs.type &&
               lhs.lanName == rhs.lanName &&
               lhs.online == rhs.online
    }
}
