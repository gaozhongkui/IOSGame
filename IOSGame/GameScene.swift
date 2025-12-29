//
//  GameScene.swift
//  IOSGame
//
//  Created by gaozhongkui on 2025/12/29.
//

import GameplayKit
import SpriteKit


class GameScene: SKScene {
    
    // 引用液体节点，方便后续控制水位
    private var liquid: SKSpriteNode?
    private let bottleHeight: CGFloat = 400
    private var currentPercent: CGFloat = 0.0
    
    override func didMove(to view: SKView) {
        // 设置背景色
        self.backgroundColor = .darkGray
        
        let bottleNode = createFilledBottle()
        bottleNode.position = CGPoint(x: frame.midX, y: frame.midY)
        addChild(bottleNode)
    }
    
    private func createFilledBottle() -> SKNode {
        let container = SKNode()
        
        let bottleTexture = SKTexture(imageNamed: "bottle")
        let bottleWidth = (bottleTexture.size().width * bottleHeight) / bottleTexture.size().height
        let bottleSize = CGSize(width: bottleWidth, height: bottleHeight)
        
        let cropNode = SKCropNode()
        
        let mask = SKSpriteNode(texture: bottleTexture)
        mask.size = bottleSize
        cropNode.maskNode = mask
        
        let liquidColor = UIColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.8)
        let liquidNode = SKSpriteNode(color: liquidColor, size: bottleSize)
        liquidNode.name = "liquid"
       
        liquidNode.position = CGPoint(x: 0, y: -bottleHeight)
        self.liquid = liquidNode
      
        let bottleBorder = SKSpriteNode(texture: bottleTexture)
        bottleBorder.size = bottleSize
        bottleBorder.zPosition = 10
        bottleBorder.alpha = 0.6
       
        cropNode.addChild(liquidNode)
        container.addChild(cropNode)
        container.addChild(bottleBorder)
        
        return container
    }
    
    func fill(to percent: CGFloat) {
        guard let liquid = liquid else { return }
        
        let targetY = -bottleHeight + (bottleHeight * percent)
        
        let moveAction = SKAction.moveTo(y: targetY, duration: 0.5)
        moveAction.timingMode = .easeInEaseOut
        liquid.run(moveAction)
    }
    
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentPercent += 0.2
        if currentPercent > 1.0 { currentPercent = 0.0 } 
        
        fill(to: currentPercent)
    }
}
