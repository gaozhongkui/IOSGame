//
//  GameScene.swift
//  IOSGame
//
//  Created by gaozhongkui on 2025/12/29.
//

import GameplayKit
import SpriteKit

class GameScene: SKScene {
    var myBottle: LiquidBottleNode?

    override func didMove(to view: SKView) {
        backgroundColor = .darkGray

        // 创建并添加瓶子
        let bottle = LiquidBottleNode(bottleImageName: "bottle", height: 400)
        bottle.position = CGPoint(x: frame.midX, y: frame.midY)
        addChild(bottle)
        myBottle = bottle
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let bottle = myBottle else { return }
        let location = touch.location(in: self)

        if location.x > frame.midX {
            bottle.fillNextSlot()
        } else {
            bottle.pourAnimation(toAngle: .pi / 2, duration: 1.2)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        //  myBottle?.pourAnimation(toAngle: .pi / 3, duration: 1.2)
    }
}
