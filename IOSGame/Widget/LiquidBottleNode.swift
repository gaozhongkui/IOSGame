//
//  LiquidBottleNode.swift
//  IOSGame
//
//  Created by gaozhongkui on 2025/12/30.
//

import SpriteKit

class LiquidBottleNode: SKNode {
    // MARK: - 私有属性
    private var bottleContainer: SKNode!
    private var liquid: SKSpriteNode?
    private let bottleHeight: CGFloat
    private var currentPercent: CGFloat = 0.0
    
    // 独立的 Uniforms，确保每个瓶子的状态独立
    private let percentUniform = SKUniform(name: "u_percent", float: 0.0)
    private let rotationUniform = SKUniform(name: "u_rotation", float: 0.0)
    
    // MARK: - 初始化
    init(bottleImageName: String, height: CGFloat) {
        self.bottleHeight = height
        super.init()
        setupBottle(imageName: bottleImageName)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 设置方法
    private func setupBottle(imageName: String) {
        let bottleTexture = SKTexture(imageNamed: imageName)
        let bottleWidth = (bottleTexture.size().width * bottleHeight) / bottleTexture.size().height
        let bottleSize = CGSize(width: bottleWidth, height: bottleHeight)
        
        let cropNode = SKCropNode()
        let mask = SKSpriteNode(texture: bottleTexture, size: bottleSize)
        cropNode.maskNode = mask
        
        // 生成纹理
        let paletteTexture = createEightSlotTexture()
        
        // 液体节点
        let liquidNode = SKSpriteNode(color: .white, size: bottleSize)
        
        let shaderSource = """
        void main() {
            vec2 uv = v_tex_coord;
            float time = u_time * 2.5;
            
            float tilt = (uv.x - 0.5) * tan(u_rotation);
            float wave = sin(uv.x * 7.0 + time) * 0.008;
            
            float currentLimit = u_percent - 0.02 + wave - tilt; 
            if (uv.y > currentLimit) discard;

            vec4 color = texture2D(u_palette, vec2(0.5, uv.y));
            
            float slotBoundary = fract(uv.y * 8.0);
            if (slotBoundary < 0.03 || slotBoundary > 0.97) {
                color.rgb *= 0.8;
            }

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
        self.liquid = liquidNode
        
        let bottleBorder = SKSpriteNode(texture: bottleTexture, size: bottleSize)
        bottleBorder.zPosition = 10
        bottleBorder.alpha = 0.4
        
        cropNode.addChild(liquidNode)
        self.addChild(cropNode)
        self.addChild(bottleBorder)
    }

    private func createEightSlotTexture() -> SKTexture {
        let colors: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple, .brown]
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

    // MARK: - 外部调用接口
    
    /// 填充下一个槽位
    func fillNextSlot(duration: TimeInterval = 0.5) {
        let startP = currentPercent
        let targetP = min(currentPercent + 0.125, 1.0)
        
        let fillAction = SKAction.customAction(withDuration: duration) { _, elapsedTime in
            let t = elapsedTime / CGFloat(duration)
            let currentP = startP + (targetP - startP) * t
            self.percentUniform.floatValue = Float(currentP)
        }
        fillAction.timingMode = .easeInEaseOut
        self.run(fillAction)
        currentPercent = targetP
    }
    
    /// 倾斜瓶子
    func tilt(to angle: CGFloat, duration: TimeInterval = 0.4) {
        let rotate = SKAction.rotate(toAngle: angle, duration: duration)
        let sync = SKAction.customAction(withDuration: duration) { _, _ in
            self.rotationUniform.floatValue = Float(self.zRotation)
        }
        self.run(SKAction.group([rotate, sync]))
    }
}
