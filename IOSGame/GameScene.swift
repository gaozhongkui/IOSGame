//
//  GameScene.swift
//  IOSGame
//
//  Created by gaozhongkui on 2025/12/29.
//

import GameplayKit
import SpriteKit

class GameScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .white
        let bottle = createBottle()
        addChild(bottle)
    }

    private func createBottle() -> SKNode {
        let bottle = SKSpriteNode(imageNamed: "bottle")
        let bottleHeight: CGFloat = 400
        let bottleWidth = (bottle.size.width * bottleHeight) / bottle.size.height
        bottle.size = CGSize(width: bottleWidth, height: bottleHeight)
        bottle.texture?.filteringMode = .linear
        return bottle
    }
}

