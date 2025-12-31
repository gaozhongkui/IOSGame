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
            float rot = u_rotation;
        
            // 1. 计算旋转后的投影高度
            float cosR = cos(rot);
            float sinR = sin(rot);
            float rotatedY = (uv.y - 0.5) * cosR + (uv.x - 0.5) * sinR + 0.5;
        
            // 2. 计算液位限制
            float wave = sin(uv.x * 7.0 + u_time * 2.5) * 0.005 * cosR;
            float currentLimit = u_percent + wave;
        
            // 3. 裁剪：无论如何，超过液面的部分都要丢弃
            if (rotatedY > currentLimit) discard;

            // --- 核心修正：平滑切换采样逻辑 ---
            // 计算旋转程度的绝对值 (0.0 到 1.0 之间)
            float rotFactor = abs(sinR); 
        
            // 我们混合两种采样方式：
            // 方式 A (直立时): 直接按高度采样 uv.y，保持槽位固定
            // 方式 B (倾斜时): 按比例采样 rotatedY / currentLimit，实现平铺
            float samplePos = mix(uv.y, rotatedY / (currentLimit + 0.001), rotFactor);
        
            // 确保采样不越界
            samplePos = clamp(samplePos, 0.0, 1.0);
        
            vec4 color = texture2D(u_palette, vec2(0.5, samplePos));
        
            // 4. 刻度线 (固定在瓶身上，所以用 uv.y)
            float slotBoundary = fract(uv.y * u_slot_count);
            if (slotBoundary < 0.03 || slotBoundary > 0.97) {
                color.rgb *= 0.8;
            }

            // 5. 液面边缘高亮
            if (rotatedY > currentLimit - 0.015) {
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

        let startP = currentPercent
        let nextSlots = currentSlots - 1
        let targetP = CGFloat(nextSlots) / CGFloat(maxSlots)
        let topColor = getCurrentTopColor()
        let angle: CGFloat = .pi / 2
        
        // 1. 倾斜动作 (0.3秒)：此时 u_percent 不变，你会看到 2 槽液体由于重力“荡”向瓶口并平铺
        let tiltAction = SKAction.customAction(withDuration: 0.3) { [weak self] _, elapsedTime in
            let t = elapsedTime / 0.3
            let currentRot = angle * t
            self?.zRotation = currentRot
            self?.rotationUniform.floatValue = Float(currentRot)
        }

        // 2. 倒出动作：percent 线性减小
        let draining = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            let t = elapsedTime / CGFloat(duration)
            let cp = startP - (startP - targetP) * t
            self?.percentUniform.floatValue = Float(cp)
        }

        let resetAction = SKAction.customAction(withDuration: 0.3) { [weak self] _, elapsedTime in
            let t = 1.0 - (elapsedTime / 0.3)
            let currentRot = angle * t
            self?.zRotation = currentRot
            self?.rotationUniform.floatValue = Float(currentRot)
        }

        run(SKAction.sequence([
            tiltAction,
            SKAction.group([
                SKAction.run { [weak self] in self?.startPourParticle(color: topColor, targetY: 400) },
                draining
            ]),
            SKAction.run { [weak self] in self?.stopPourParticle() },
            resetAction,
            SKAction.run { [weak self] in
                // 归位后更新逻辑
                self?.currentSlots = nextSlots
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

    /// 传入 targetY: 目标瓶口在父容器中的 Y 坐标
    private func startPourParticle(color: UIColor, targetY: CGFloat) {
        stopPourParticle()
        guard let parentNode = parent else { return }
        
        let emitter = SKEmitterNode()
        
        // --- 1. 基础物理参数 ---
        let gravity: CGFloat = 1800 // 重力加速度
        emitter.yAcceleration = -gravity
        emitter.particleSpeed = 150 // 初始喷出速度
        emitter.particleSpeedRange = 20
        
        // --- 2. 计算动态起点 ---
        let mouthRadius: CGFloat = 15
        let offsetX = (zRotation > 0) ? -mouthRadius : mouthRadius
        let startPointInBottle = CGPoint(x: offsetX, y: (bottleHeight / 2) - 5)
        let startPointInParent = convert(startPointInBottle, to: parentNode)
        
        // --- 3. 核心数学：计算生命周期 ---
        // 计算垂直下落距离 h
        let dropDistance = abs(startPointInParent.y - targetY)
        
        // 自由落体近似公式：t = sqrt(2h/g)
        // 加上调节系数 0.95 是为了抵消 particleSpeed 带来的向下初速度
        var calculatedLifetime = sqrt(2.0 * dropDistance / gravity) * 0.95
        
        // 防止极端情况下 lifetime 为 0
        calculatedLifetime = max(0.1, calculatedLifetime)
        
        emitter.particleLifetime = calculatedLifetime
        emitter.particleLifetimeRange = 0.05 // 极小的随机感，让切口不至于像刀削一样齐
        
        // --- 4. 视觉优化 ---
        emitter.particleTexture = createCircleTexture(radius: 7, color: .white)
        emitter.particleBirthRate = 45
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1.0
        
        // 让粒子在到达终点前快速变透明，产生“没入”感
        // 如果想要粒子到达时依然凝实，可以把这个值调小
        emitter.particleAlphaSpeed = -1.0 / calculatedLifetime
        
        emitter.particleScale = 0.5
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -0.2
        
        // --- 5. 发射方向 ---
        let baseAngle = (zRotation > 0) ? CGFloat.pi : 0
        emitter.emissionAngle = baseAngle
        emitter.emissionAngleRange = 0.1
        
        // --- 6. 属性设置 ---
        emitter.position = startPointInParent
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
