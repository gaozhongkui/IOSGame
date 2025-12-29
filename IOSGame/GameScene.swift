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
    
    // 传递当前填充比例，用于 Shader 还原绝对坐标
    private let percentUniform = SKUniform(name: "u_percent", float: 0.0)
    
    override func didMove(to view: SKView) {
        backgroundColor = .darkGray
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
        
        // 生成 8 色色卡
        let paletteTexture = createEightColorTexture()
        
        let liquidNode = SKSpriteNode(color: .white, size: bottleSize)
        
        let shaderSource = """
        void main() {
            vec2 uv = v_tex_coord;
            float time = u_time * 2.5;
            
            // 1. 水波纹逻辑（仅作用于液体顶端）
            float wave = sin(uv.x * 7.0 + time) * 0.008;
            float surfaceLine = 0.98 + wave; 
            if (uv.y > surfaceLine) discard;

            // 2. 核心逻辑：还原绝对颜色位置
            // 因为 liquidNode 的高度在变，uv.y 永远是 0~1。
            // 我们通过 u_percent 将其还原为在整瓶中的比例位置。
            float absoluteY = uv.y * u_percent;
            
            // 3. 采样颜色
            vec4 color = texture2D(u_palette, vec2(0.5, absoluteY));
            
            // 4. 表面高光 (让最顶部的那个色块边缘发亮)
            if (uv.y > surfaceLine - 0.015) {
                color.rgb += 0.15;
            }
            
            gl_FragColor = color;
        }
        """
        
        let shader = SKShader(source: shaderSource)
        shader.addUniform(SKUniform(name: "u_palette", texture: paletteTexture))
        shader.addUniform(percentUniform)
        
        liquidNode.shader = shader
        liquidNode.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        liquidNode.position = CGPoint(x: 0, y: -bottleHeight/2)
        
        liquid = liquidNode
        
        let bottleBorder = SKSpriteNode(texture: bottleTexture)
        bottleBorder.size = bottleSize
        bottleBorder.zPosition = 10
        bottleBorder.alpha = 0.4
        
        cropNode.addChild(liquidNode)
        container.addChild(cropNode)
        container.addChild(bottleBorder)
        
        return container
    }

    private func createEightColorTexture() -> SKTexture {
        // 从下到上的 8 种颜色
        let colors: [UIColor] = [
            .systemBlue,   // 0.0 - 0.125
            .systemCyan,   // 0.125 - 0.25
            .systemTeal,   // 0.25 - 0.375
            .systemGreen,  // 0.375 - 0.5
            .systemYellow, // 0.5 - 0.625
            .systemOrange, // 0.625 - 0.75
            .systemRed,    // 0.75 - 0.875
            .systemPurple  // 0.875 - 1.0
        ]
        let size = CGSize(width: 1, height: 8)
        UIGraphicsBeginImageContext(size)
        for (i, color) in colors.enumerated() {
            let rect = CGRect(x: 0, y: i, width: 1, height: 1)
            color.setFill()
            UIRectFill(rect)
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return SKTexture(image: image!)
    }
    
    func fill(to percent: CGFloat) {
        guard let liquid = liquid else { return }
        let safePercent = max(0.001, min(1.0, percent))
        
        // 更新 Uniform
        percentUniform.floatValue = Float(safePercent)
        
        // 执行动画
        let newHeight = bottleHeight * safePercent
        let resizeAction = SKAction.resize(toHeight: newHeight, duration: 0.8)
        resizeAction.timingMode = .easeInEaseOut
        liquid.run(resizeAction)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentPercent += 0.125
        if currentPercent > 1.0 { currentPercent = 0.125 }
        fill(to: currentPercent)
    }
}
