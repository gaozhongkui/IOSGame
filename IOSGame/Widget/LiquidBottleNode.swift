//
//  LiquidBottleNode.swift
//  IOSGame
//
//  Created by gaozhongkui on 2025/12/30.
//

import SpriteKit

class LiquidBottleNode: SKNode {
    // MARK: - 属性
    private var liquid: SKSpriteNode?
    private let bottleHeight: CGFloat
    private var currentPercent: CGFloat = 0.0
    private var pourEmitter: SKEmitterNode?
    
    // 颜色配置（从下往上）
    private let slotColors: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple, .brown]
    
    // Uniforms
    private let percentUniform = SKUniform(name: "u_percent", float: 0.0)
    private let rotationUniform = SKUniform(name: "u_rotation", float: 0.0)
    
    // MARK: - 初始化
    init(bottleImageName: String, height: CGFloat) {
        self.bottleHeight = height
        super.init()
        setupBottle(imageName: bottleImageName)
    }
    
    required init?(coder aDecoder: NSCoder) { fatalError("init") }
    
    // MARK: - 设置方法
    private func setupBottle(imageName: String) {
        let bottleTexture = SKTexture(imageNamed: imageName)
        let ratio = bottleTexture.size().width / bottleTexture.size().height
        let bottleSize = CGSize(width: bottleHeight * ratio, height: bottleHeight)
        
        // 1. 裁剪节点（限制液体在瓶内）
        let cropNode = SKCropNode()
        cropNode.maskNode = SKSpriteNode(texture: bottleTexture, size: bottleSize)
        
        // 2. 液体 Shader
        let shaderSource = """
        // 修改后的 Shader 关键部分
        void main() {
            vec2 uv = v_tex_coord;
            float time = u_time * 2.5;
            
            // --- 修复点：限制角度在 -1.45 到 1.45 弧度之间（约 ±83 度） ---
            // 这样可以避免 tan(pi/2) 导致的数值崩溃
            float safeRotation = clamp(u_rotation, -1.45, 1.45);
            float tilt = (uv.x - 0.5) * tan(safeRotation);
            
            float wave = sin(uv.x * 7.0 + time) * 0.008;
            
            // 计算液体边界
            float currentLimit = u_percent - 0.02 + wave - tilt; 
            
            if (uv.y > currentLimit) discard;

            vec4 color = texture2D(u_palette, vec2(0.5, uv.y));
            
            // 槽位边界线处理
            float slotBoundary = fract(uv.y * 8.0);
            if (slotBoundary < 0.03 || slotBoundary > 0.97) {
                color.rgb *= 0.8;
            }

            // 顶层高亮处理
            if (uv.y > currentLimit - 0.02) {
                color.rgb += 0.2;
            }
            
            gl_FragColor = color;
        }
        """
        let shader = SKShader(source: shaderSource)
        shader.addUniform(SKUniform(name: "u_palette", texture: createEightSlotTexture()))
        shader.addUniform(percentUniform)
        shader.addUniform(rotationUniform)
        
        let liquidNode = SKSpriteNode(color: .white, size: bottleSize)
        liquidNode.shader = shader
        self.liquid = liquidNode
        
        // 3. 瓶子外壳
        let bottleBorder = SKSpriteNode(texture: bottleTexture, size: bottleSize)
        bottleBorder.zPosition = 10
        bottleBorder.alpha = 0.4
        
        cropNode.addChild(liquidNode)
        self.addChild(cropNode)
        self.addChild(bottleBorder)
    }

    // MARK: - 逻辑方法

    /// 倒入一层颜色
    func fillNextSlot(duration: TimeInterval = 0.5) {
        let startP = currentPercent
        let targetP = min(currentPercent + 0.125, 1.0)
        
        let fillAction = SKAction.customAction(withDuration: duration) { node, elapsedTime in
            let t = elapsedTime / CGFloat(duration)
            self.currentPercent = startP + (targetP - startP) * t
            self.percentUniform.floatValue = Float(self.currentPercent)
        }
        self.run(fillAction)
    }
    
    /// 倒出动画：包含倾斜、粒子流出、高度减少、恢复原位
    func pourAnimation(toAngle angle: CGFloat, duration: TimeInterval = 1.2) {
        guard currentPercent > 0 else { return }
        
        let startP = currentPercent
        let targetP = max(currentPercent - 0.125, 0.0)
        let topColor = getCurrentTopColor()
        
        // 第一步：快速倾斜
        let tiltDuration = duration * 0.3
        let tiltAction = SKAction.customAction(withDuration: tiltDuration) { [weak self] _, elapsedTime in
            let t = elapsedTime / CGFloat(tiltDuration)
            self?.zRotation = angle * t
            self?.rotationUniform.floatValue = Float(self?.zRotation ?? 0)
        }
        
        // 第二步：流出阶段
        let pourDuration = duration * 0.5
        let startPour = SKAction.run { [weak self] in self?.startPourParticle(color: topColor) }
        let draining = SKAction.customAction(withDuration: pourDuration) { [weak self] _, elapsedTime in
            let t = elapsedTime / CGFloat(pourDuration)
            let cp = startP - (startP - targetP) * t
            self?.currentPercent = cp
            self?.percentUniform.floatValue = Float(cp)
        }
        
        // 第三步：停止并回正
        let stopPour = SKAction.run { [weak self] in self?.stopPourParticle() }
        let resetAction = SKAction.customAction(withDuration: 0.3) { [weak self] _, elapsedTime in
            let t = 1.0 - (elapsedTime / 0.3)
            self?.zRotation = angle * t
            self?.rotationUniform.floatValue = Float(self?.zRotation ?? 0)
        }
        
        self.run(SKAction.sequence([
            tiltAction,
            SKAction.group([startPour, draining]),
            stopPour,
            resetAction
        ]))
    }

    // MARK: - 粒子系统（纯代码实现）
    private func startPourParticle(color: UIColor) {
        stopPourParticle()
        
        let emitter = SKEmitterNode()
        
        // 1. 生成更大的圆形纹理 (半径从 4 增加到 12)
        emitter.particleTexture = createCircleTexture(radius: 12, color: .white)
        
        // 2. 数量与寿命
        emitter.particleBirthRate = 80  // 颗粒变大后，速率可以稍微调低，防止过于拥挤
        emitter.particleLifetime = 1.2
        
        // 3. 速度与角度
        emitter.particleSpeed = 250
        emitter.particleSpeedRange = 80
        // 这里的角度需要根据瓶子 zRotation 动态调整（如果是向左倒）
        emitter.emissionAngle = (self.zRotation > 0) ? .pi : 0
        emitter.emissionAngleRange = 0.2
        
        // 4. 颜色与混合
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1.0
        
        // 5. 核心：改大尺寸
        emitter.particleScale = 0.8         // 初始缩放比例
        emitter.particleScaleRange = 0.4    // 随机大小，让颗粒看起来不那么死板
        emitter.particleScaleSpeed = -0.5   // 飞出后逐渐变小
        
        // 6. 物理感
//        emitter.yAcceleration = -1000       // 更强的重力，像液体坠落
        emitter.particleAlphaSpeed = -0.6   // 消失前稍微变透明
        
        // 7. 位置：确保在瓶口位置
        emitter.position = CGPoint(x: 0, y: bottleHeight / 2)
        emitter.zPosition = 15 // 确保在瓶子图层之上
        
        self.addChild(emitter)
        self.pourEmitter = emitter
    }
    
    private func stopPourParticle() {
        pourEmitter?.particleBirthRate = 0
        let wait = SKAction.wait(forDuration: 1.0)
        let remove = SKAction.removeFromParent()
        pourEmitter?.run(SKAction.sequence([wait, remove]))
        pourEmitter = nil
    }

    // MARK: - 辅助绘图
    
    private func createCircleTexture(radius: CGFloat, color: UIColor) -> SKTexture {
        let size = CGSize(width: radius * 2, height: radius * 2)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return SKTexture(image: image!)
    }
    
    private func createEightSlotTexture() -> SKTexture {
        let size = CGSize(width: 1, height: 256)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()!
        let slotH = size.height / 8.0
        for i in 0..<8 {
            context.setFillColor(slotColors[i].cgColor)
            context.fill(CGRect(x: 0, y: CGFloat(i) * slotH, width: 1, height: slotH))
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return SKTexture(image: image!)
    }
    
    private func getCurrentTopColor() -> UIColor {
        // 计算当前水位在哪一层
        let index = Int(ceil(currentPercent * 8) - 1)
        let safeIndex = max(0, min(slotColors.count - 1, index))
        return slotColors[safeIndex]
    }
}
