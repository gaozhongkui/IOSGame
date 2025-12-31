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
            float tilt = (uv.x - 0.5) * tan(safeRotation) * 0.8;
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
        guard currentSlots > 0 else { return }

        // 1. 记录起始和结束
        let startP = currentPercent
        let nextSlots = currentSlots - 1 // 计算下一阶段的槽位数
        let targetP = CGFloat(nextSlots) / CGFloat(maxSlots)
        
        let topColor = getCurrentTopColor()
        let angle: CGFloat = .pi / 2
        
        // 2. 动画序列
        let tiltAction = SKAction.customAction(withDuration: 0.3) { [weak self] _, elapsedTime in
            let t = elapsedTime / 0.3
            self?.zRotation = angle * t
            self?.rotationUniform.floatValue = Float(self?.zRotation ?? 0)
        }

        let draining = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            let t = elapsedTime / CGFloat(duration)
            // 关键：在倒水过程中，百分比从 startP 线性降到 targetP
            let cp = startP - (startP - targetP) * t
            self?.percentUniform.floatValue = Float(cp)
        }

        let resetAction = SKAction.customAction(withDuration: 0.3) { [weak self] _, elapsedTime in
            let t = 1.0 - (elapsedTime / 0.3)
            self?.zRotation = angle * t
            self?.rotationUniform.floatValue = Float(self?.zRotation ?? 0)
        }

        run(SKAction.sequence([
            tiltAction,
            SKAction.group([
                SKAction.run { [weak self] in self?.startPourParticle(color: topColor) },
                draining
            ]),
            SKAction.run { [weak self] in self?.stopPourParticle() },
            resetAction,
            SKAction.run { [weak self] in
                // 动画彻底结束后，正式更新逻辑数据
                self?.currentSlots = nextSlots
                // 如果这一层倒完了，把 slotColors 对应位置设为透明
                if nextSlots < (self?.slotColors.count ?? 0) {
                    self?.slotColors[nextSlots] = .clear
                    self?.updatePalette()
                }
            }
        ]))
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
        
        // 1. 纹理：稍微调小一点点，让液滴更精致
        emitter.particleTexture = createCircleTexture(radius: 8, color: .white)
        
        // 2. 密度优化：大幅降低出生率 (从 80-100 降到 20-30)
        // 这样粒子之间会有明显的间隙，看起来更像水滴
        emitter.particleBirthRate = 25
        emitter.particleLifetime = 1.0
        
        // 3. 速度与扩散：增加随机性，让液滴散开一点
        emitter.particleSpeed = 350
        emitter.particleSpeedRange = 150 // 让有的快有的慢
        emitter.emissionAngle = (zRotation > 0) ? .pi : 0
        emitter.emissionAngleRange = 0.25 // 稍微散开的角度
        
        // 4. 颜色
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1.0
        
        // 5. 尺寸变化：让液滴在飞行过程中变小
        emitter.particleScale = 0.5
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -0.4 // 飞出后逐渐变小消失
        
        // 6. 物理感（关键）：加入重力感，让液滴呈抛物线落下
        emitter.yAcceleration = -800 // 负值代表向下坠落
        
        // 7. 混合模式：如果是液体，通常用 Alpha 混合即可
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -0.8 // 快速淡出
        
        let tipPositionInBottle = CGPoint(x: 0, y: bottleHeight / 2)
            
        guard let parentNode = parent else { return }
        let tipPositionInParent = convert(tipPositionInBottle, to: parentNode)
        emitter.position = tipPositionInParent
        emitter.targetNode = parentNode
        emitter.zPosition = zPosition + 1
        parentNode.addChild(emitter)

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
