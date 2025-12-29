//
//  GameScene.swift
//  IOSGame
//
//  Created by gaozhongkui on 2025/12/29.
//

import GameplayKit
import SpriteKit

class GameScene: SKScene {
    private var liquid: SKSpriteNode?
    private let bottleHeight: CGFloat = 400
    private var currentPercent: CGFloat = 0.0
    
    override func didMove(to view: SKView) {
        // 设置背景色
        backgroundColor = .darkGray
        
        let bottleNode = createFilledBottle()
        bottleNode.position = CGPoint(x: frame.midX, y: frame.midY)
        addChild(bottleNode)
    }
    
    private func createFilledBottle() -> SKNode {
        let container = SKNode()
        
        // 1. 获取瓶子纹理
        let bottleTexture = SKTexture(imageNamed: "bottle")
        let bottleWidth = (bottleTexture.size().width * bottleHeight) / bottleTexture.size().height
        let bottleSize = CGSize(width: bottleWidth, height: bottleHeight)
        
        // 2. 创建遮罩裁切节点
        let cropNode = SKCropNode()
        let mask = SKSpriteNode(texture: bottleTexture)
        mask.size = bottleSize
        cropNode.maskNode = mask
        
        // 3. 创建液体
        // 使用一个小技巧：给一个基础颜色纹理，确保 Shader 坐标映射正确
        let liquidColor = UIColor(red: 0.1, green: 0.6, blue: 1.0, alpha: 0.85)
        let liquidNode = SKSpriteNode(color: .white, size: bottleSize)
        liquidNode.color = liquidColor
        liquidNode.colorBlendFactor = 1.0
        liquidNode.name = "liquid"
        
        // --- 极简平缓波纹 Shader ---
        let shaderSource = """
        void main() {
            vec2 uv = v_tex_coord;
        
            // 降低时间流速，让波动变慢
            float time = u_time * 2.5; 
        
            // --- 核心微调参数 ---
            // 振幅从 0.02 降到 0.008 (非常微弱的波动)
            float amp1 = 0.008; 
            float freq1 = 6.0;
        
            // 第二层波更加微弱，增加波动的不规则性
            float amp2 = 0.004;
            float freq2 = 12.0;

            float wave = sin(uv.x * freq1 + time) * amp1 
                       + cos(uv.x * freq2 - time * 0.8) * amp2;
        
            // 设定水位线，0.98 几乎接近顶部边缘
            float surfaceLine = 0.98 + wave;
        
            if (uv.y > surfaceLine) {
                discard;
            }
        
            // 添加一个极细的亮边，让水面看起来有质感
            vec4 color = v_color_mix;
            if (uv.y > surfaceLine - 0.015) {
                color.rgb += 0.1; 
            }
        
            gl_FragColor = color;
        }
        """
        liquidNode.shader = SKShader(source: shaderSource)
        
        // 设置锚点为底部
        liquidNode.anchorPoint = CGPoint(x: 0.5, y: 0.0)  // 底部固定
        liquidNode.position = CGPoint(x: 0, y: -bottleHeight/2) // 对齐瓶底

        
        liquid = liquidNode
        
        // 4. 瓶子外框
        let bottleBorder = SKSpriteNode(texture: bottleTexture)
        bottleBorder.size = bottleSize
        bottleBorder.zPosition = 10
        bottleBorder.alpha = 0.4 // 降低边框透明度，让液体更显眼
        
        cropNode.addChild(liquidNode)
        container.addChild(cropNode)
        container.addChild(bottleBorder)
        
        return container
    }
    
    func fill(to percent: CGFloat) {
        guard let liquid = liquid else { return }

        let newHeight = bottleHeight * percent
        let resizeAction = SKAction.resize(toHeight: newHeight, duration: 1.0)
        resizeAction.timingMode = .easeInEaseOut

        // 惯性晃动
        let tiltRight = SKAction.rotate(toAngle: 0.02, duration: 0.25)
        let tiltLeft = SKAction.rotate(toAngle: -0.02, duration: 0.5)
        let resetTilt = SKAction.rotate(toAngle: 0, duration: 0.25)
        let shakeSequence = SKAction.sequence([tiltRight, tiltLeft, resetTilt])

        liquid.run(resizeAction)
        liquid.run(shakeSequence)
    }

    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentPercent += 0.2
        if currentPercent > 1.05 { currentPercent = 0.0 } // 稍微超过1让水位溢满
        
        fill(to: currentPercent)
    }
}
