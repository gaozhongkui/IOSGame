//
//  Color+Ex.swift
//  IOSGame
//
//  Created by gaozhongkui on 2025/12/31.
//

import SpriteKit

extension SKColor {
    static var random: SKColor {
        return SKColor(hue: .random(in: 0...1), saturation: .random(in: 0.7...1), brightness: .random(in: 0.8...1), alpha: 1.0)
    }
}
