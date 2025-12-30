//
//  GameScene.swift
//  IOSGame
//
//  Created by gaozhongkui on 2025/12/29.
//

import GameplayKit
import SpriteKit

class GameScene: SKScene {
    private var bottleContainer: SKNode!
    private var liquid: SKSpriteNode?
    private let bottleHeight: CGFloat = 400
    private var currentPercent: CGFloat = 0.0 // 0.0 到 1.0 之间
    
    // 关键 Uniform：控制 Shader 内部渲染的水位高度
    private let percentUniform = SKUniform(name: "u_percent", float: 0.0)
    private let rotationUniform = SKUniform(name: "u_rotation", float: 0.0)
    
    override func didMove(to view: SKView) {
        backgroundColor = .darkGray
        bottleContainer = createFilledBottle()
        bottleContainer.position = CGPoint(x: frame.midX, y: frame.midY)
        addChild(bottleContainer)
    }
    
    private func createFilledBottle() -> SKNode {
        let container = SKNode()
        let bottleTexture = SKTexture(imageNamed: "bottle")
        let bottleWidth = (bottleTexture.size().width * bottleHeight) / bottleTexture.size().height
        let bottleSize = CGSize(width: bottleWidth, height: bottleHeight)
        
        let cropNode = SKCropNode()
        let mask = SKSpriteNode(texture: bottleTexture, size: bottleSize)
        cropNode.maskNode = mask
        
        // 1. 生成 8 个硬边缘槽位的纹理
        let paletteTexture = createEightSlotTexture()
        
        // 2. 液体节点：大小始终填满瓶子，显隐由 Shader 控制
        let liquidNode = SKSpriteNode(color: .white, size: bottleSize)
        
        let shaderSource = """
        void main() {
            vec2 uv = v_tex_coord;
            float time = u_time * 2.5;
            
            // A. 倾斜补偿
            float tilt = (uv.x - 0.5) * tan(u_rotation);
            float wave = sin(uv.x * 7.0 + time) * 0.008;
            
            // B. 显隐逻辑：核心改动
            // 我们不再改变 Node 的高度，而是由 u_percent 直接在 Shader 里切分
            // 如果当前的 Y 坐标大于设定的水位，就消失
            float currentLimit = u_percent - 0.02 + wave - tilt; 
            if (uv.y > currentLimit) discard;

            // C. 固定颜色采样：核心改动
            // 每一个 uv.y 的区间（如 0.0-0.125）永远对应 palette 里的同一个色块
            vec4 color = texture2D(u_palette, vec2(0.5, uv.y));
            
            // D. 槽位分割线：让 8 个槽看起来是分开的
            float slotBoundary = fract(uv.y * 8.0);
            if (slotBoundary < 0.03 || slotBoundary > 0.97) {
                color.rgb *= 0.8; // 槽位间的黑线
            }

            // E. 顶层液面高亮
            if (uv.y > currentLimit - 0.02) {
                color.rgb += 0.2;
            }
            
            gl_FragColor = color;
        }
        """
        
        let shader = SKShader(source: shaderSource)
        shader.addUniform(SKUniform(name: "u_palette", texture: paletteTexture))
        shader.addUniform(percentUniform)
        shader.addUniform(rotationUniform)
        
        liquidNode.shader = shader
        // 保持中心锚点，方便后续旋转
        liquidNode.position = .zero
        liquid = liquidNode
        
        let bottleBorder = SKSpriteNode(texture: bottleTexture, size: bottleSize)
        bottleBorder.zPosition = 10
        bottleBorder.alpha = 0.4
        
        cropNode.addChild(liquidNode)
        container.addChild(cropNode)
        container.addChild(bottleBorder)
        
        return container
    }

    private func createEightSlotTexture() -> SKTexture {
        let colors: [UIColor] = [
            .systemRed, .systemOrange, .systemYellow, .systemGreen,
            .systemTeal, .systemBlue, .systemPurple, .brown
        ]
        
        let size = CGSize(width: 1, height: 256)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()!
        
        let slotHeight = size.height / 8.0
        for i in 0..<8 {
            let rect = CGRect(x: 0, y: CGFloat(i) * slotHeight, width: size.width, height: slotHeight)
            context.setFillColor(colors[i].cgColor)
            context.fill(rect)
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        let tex = SKTexture(image: image!)
        tex.filteringMode = .nearest
        return tex
    }
    
    // 增加一个槽位
    func fillNextSlot() {
        let startP = currentPercent
        let targetP = min(currentPercent + 0.125, 1.0)
        let duration: TimeInterval = 0.5
        
        // 只需要改变 Uniform，Shader 会自动处理高度和颜色
        let fillAction = SKAction.customAction(withDuration: duration) { _, elapsedTime in
            let t = elapsedTime / CGFloat(duration)
            let currentP = startP + (targetP - startP) * t
            self.percentUniform.floatValue = Float(currentP)
        }
        fillAction.timingMode = .easeInEaseOut
        run(fillAction)
        currentPercent = targetP
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        if location.x > frame.midX {
            fillNextSlot()
        } else {
            // 倾斜模拟
            let rotate = SKAction.rotate(toAngle: .pi/4, duration: 0.4)
            let sync = SKAction.customAction(withDuration: 0.4) { _, _ in
                self.rotationUniform.floatValue = Float(self.bottleContainer.zRotation)
            }
            bottleContainer.run(SKAction.group([rotate, sync]))
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let rotate = SKAction.rotate(toAngle: 0, duration: 0.3)
        let sync = SKAction.customAction(withDuration: 0.3) { _, _ in
            self.rotationUniform.floatValue = Float(self.bottleContainer.zRotation)
        }
        bottleContainer.run(SKAction.group([rotate, sync]))
    }
}
