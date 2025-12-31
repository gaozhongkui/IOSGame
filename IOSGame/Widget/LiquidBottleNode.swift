//
//  LiquidBottleNode.swift
//  IOSGame
//
//  Created by gaozhongkui on 2025/12/30.
//

import SpriteKit

class LiquidBottleNode: SKNode {
    private var liquid: SKSpriteNode?
    private let bottleHeight: CGFloat
    private let maxSlots: Int = 8
    private var currentSlots: Int = 0
    private var pourEmitter: SKEmitterNode?
    
    private var slotColors: [UIColor] = []

    // Uniforms
    private let percentUniform = SKUniform(name: "u_percent", float: 0.0)
    private let rotationUniform = SKUniform(name: "u_rotation", float: 0.0)
    private let slotCountUniform = SKUniform(name: "u_slot_count", float: 8.0)
    
    /// 计算属性：将整数槽位转换为 Shader 比例 (0.0 - 1.0)
    private var currentPercent: CGFloat {
        return CGFloat(currentSlots) / CGFloat(maxSlots)
    }
   
    init(bottleImageName: String, height: CGFloat) {
        self.bottleHeight = height
        super.init()
        setupBottle(imageName: bottleImageName)
    }
    
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init") }
    
    func setInitDefaultColor() {
        // 初始化 8 个透明空位
        slotColors = Array(repeating: .clear, count: maxSlots)
        updatePalette()
    }

    private func setupBottle(imageName: String) {
        let bottleTexture = SKTexture(imageNamed: imageName)
        let ratio = bottleTexture.size().width / bottleTexture.size().height
        let bottleSize = CGSize(width: bottleHeight * ratio, height: bottleHeight)
        
        let cropNode = SKCropNode()
        cropNode.maskNode = SKSpriteNode(texture: bottleTexture, size: bottleSize)
        
        let shaderSource = """
        void main() {
            vec2 uv = v_tex_coord;
            float time = u_time * 2.5;
            float safeRotation = clamp(u_rotation, -1.45, 1.45);
            float tilt = (uv.x - 0.5) * tan(safeRotation);
            float wave = sin(uv.x * 7.0 + time) * 0.008;
            float currentLimit = u_percent - 0.02 + wave - tilt; 
        
            if (uv.y > currentLimit) discard;

            vec4 color = texture2D(u_palette, vec2(0.5, uv.y));
            float slotBoundary = fract(uv.y * u_slot_count);
            if (slotBoundary < 0.03 || slotBoundary > 0.97) {
                color.rgb *= 0.8;
            }

            if (uv.y > currentLimit - 0.015) {
                color.rgb += 0.2;
            }
            gl_FragColor = color;
        }
        """
        let shader = SKShader(source: shaderSource)
        shader.addUniform(SKUniform(name: "u_palette", texture: createDynamicSlotTexture()))
        shader.addUniform(percentUniform)
        shader.addUniform(rotationUniform)
        shader.addUniform(slotCountUniform)
        
        let liquidNode = SKSpriteNode(color: .white, size: bottleSize)
        liquidNode.shader = shader
        liquid = liquidNode
        
        let bottleBorder = SKSpriteNode(texture: bottleTexture, size: bottleSize)
        bottleBorder.zPosition = 10
        bottleBorder.alpha = 0.4
        
        cropNode.addChild(liquidNode)
        addChild(cropNode)
        addChild(bottleBorder)
    }
    
    /// 倒入一层颜色
    func addFullSlot(color: SKColor, duration: TimeInterval = 0.8) {
        guard currentSlots < maxSlots else { return }

        // 1. 先记录动画起始状态
        let startP = currentPercent
        
        // 2. 更新逻辑数据：找到位置填入颜色并增加槽位计数
        if currentSlots < slotColors.count {
            slotColors[currentSlots] = color
        } else {
            slotColors.append(color)
        }
        currentSlots += 1
        
        // 3. 记录动画目标状态
        let targetP = currentPercent
        
        updatePalette()

        let fillAction = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            let t = elapsedTime / CGFloat(duration)
            let p = startP + (targetP - startP) * t
            self?.percentUniform.floatValue = Float(p)
        }
        run(fillAction)
    }
    
    /// 倒出一层颜色
    func pourSlot(duration: TimeInterval = 0.8) {
        // 只有有液体时才能倒出
        guard currentSlots > 0 else { return }

        let startP = currentPercent
        let topColor = getCurrentTopColor()
        
        // 计算目标：减少一个槽位后的比例
        let targetP = CGFloat(currentSlots - 1) / CGFloat(maxSlots)
        let angle: CGFloat = .pi / 2
        
        // 倾斜动画
        let tiltDuration = 0.3
        let tiltAction = SKAction.customAction(withDuration: tiltDuration) { [weak self] _, elapsedTime in
            let t = elapsedTime / CGFloat(tiltDuration)
            self?.zRotation = angle * t
            self?.rotationUniform.floatValue = Float(self?.zRotation ?? 0)
        }

        // 液体减少动画
        let draining = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            let t = elapsedTime / CGFloat(duration)
            let cp = startP - (startP - targetP) * t
            self?.percentUniform.floatValue = Float(cp)
        }

        // 粒子逻辑
        let startPour = SKAction.run { [weak self] in self?.startPourParticle(color: topColor) }
        let stopPour = SKAction.run { [weak self] in self?.stopPourParticle() }
        
        // 回正动画
        let resetAction = SKAction.customAction(withDuration: 0.3) { [weak self] _, elapsedTime in
            let t = 1.0 - (elapsedTime / 0.3)
            self?.zRotation = angle * t
            self?.rotationUniform.floatValue = Float(self?.zRotation ?? 0)
        }

        // 执行序列
        let sequence = SKAction.sequence([
            tiltAction,
            SKAction.group([startPour, draining]),
            stopPour,
            resetAction,
            SKAction.run { [weak self] in
                // 动画彻底结束后更新逻辑计数，确保下次计算准确
                self?.currentSlots -= 1
            }
        ])
        run(sequence)
    }
    
    private func updatePalette() {
        let newTexture = createDynamicSlotTexture()
        liquid?.shader?.addUniform(SKUniform(name: "u_palette", texture: newTexture))
        slotCountUniform.floatValue = Float(maxSlots)
    }

    private func createDynamicSlotTexture() -> SKTexture {
        let size = CGSize(width: 1, height: 256)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else { return SKTexture() }
        
        let slotH = size.height / CGFloat(maxSlots)
        
        for i in 0 ..< maxSlots {
            let color = i < slotColors.count ? slotColors[i] : .clear
            context.setFillColor(color.cgColor)
            
            // 修正：y=0在顶部，所以第一个颜色(i=0)应该画在最底下
            let rect = CGRect(x: 0, y: size.height - CGFloat(i + 1) * slotH, width: 1, height: slotH)
            context.fill(rect)
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image != nil ? SKTexture(image: image!) : SKTexture()
    }
    
    private func startPourParticle(color: UIColor) {
        stopPourParticle()
        let emitter = SKEmitterNode()
        emitter.particleTexture = createCircleTexture(radius: 10, color: .white)
        emitter.particleBirthRate = 100
        emitter.particleLifetime = 1.0
        emitter.particleSpeed = 300
        emitter.emissionAngle = (zRotation > 0) ? .pi : 0
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1.0
        emitter.particleScale = 0.6
        emitter.particleScaleSpeed = -0.4
        emitter.position = CGPoint(x: 0, y: bottleHeight / 2)
        emitter.zPosition = 15
        addChild(emitter)
        pourEmitter = emitter
    }
    
    private func stopPourParticle() {
        pourEmitter?.particleBirthRate = 0
        pourEmitter?.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.removeFromParent()
        ]))
        pourEmitter = nil
    }

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

    private func getCurrentTopColor() -> UIColor {
        // 增加越界检查
        let index = currentSlots - 1
        if index >= 0 && index < slotColors.count {
            return slotColors[index]
        }
        return .white
    }
}
