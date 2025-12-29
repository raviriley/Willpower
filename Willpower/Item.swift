//
//  Item.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
