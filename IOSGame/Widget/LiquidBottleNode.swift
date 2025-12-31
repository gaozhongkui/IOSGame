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
    private let maxSlots: Int = 5 // 已改为 5
    private var currentSlots: Int = 0
    private var pourEmitter: SKEmitterNode?

    private var isAnimating = false
    private var slotColors: [UIColor] = []

    // Uniforms
    private let percentUniform = SKUniform(name: "u_percent", float: 0.0)
    private let rotationUniform = SKUniform(name: "u_rotation", float: 0.0)
    private let slotCountUniform = SKUniform(name: "u_slot_count", float: 5.0) // 已改为 5.0

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

    // MARK: - 动态液位获取

    /// 获取当前瓶子“水面”在场景中的 Y 坐标
    func getLiquidSurfaceY() -> CGFloat {
        guard let parentNode = parent else { return position.y }
        // 计算瓶子底部的世界坐标 Y (假设 anchorPoint 在中心)
        let bottomY = position.y - (bottleHeight / 2)
        // 水面高度 = 底部 + (总高度 * 当前比例)
        return bottomY + (bottleHeight * currentPercent)
    }

    // MARK: - 初始化

    func setInitDefaultColor() {
        // 明确初始化为 maxSlots 长度的数组，填充透明色
        slotColors = Array(repeating: .clear, count: maxSlots)
        currentSlots = 0 // 重置当前计数
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
            float cosR = cos(rot);
            float sinR = sin(rot);
            float rotatedY = (uv.y - 0.5) * cosR + (uv.x - 0.5) * sinR + 0.5;

            float wave = sin(uv.x * 7.0 + u_time * 2.5) * 0.005 * cosR;
            float currentLimit = u_percent + wave;

            float edgeAlpha = smoothstep(currentLimit + 0.003, currentLimit - 0.003, rotatedY);
            if (edgeAlpha <= 0.0) discard;

            float rotFactor = abs(sinR); 
            // 修正采样逻辑：适配 5 槽位比例
            float samplePos = mix(uv.y, clamp(rotatedY, 0.0, u_percent - 0.001), rotFactor);
            samplePos = clamp(samplePos, 0.0, 1.0);

            vec4 color = texture2D(u_palette, vec2(0.5, samplePos));

            float slotBoundary = fract(uv.y * u_slot_count);
            if (slotBoundary < 0.03 || slotBoundary > 0.97) {
                color.rgb *= 0.8;
            }

            if (rotatedY > currentLimit - 0.015) {
                color.rgb += 0.2;
            }
            gl_FragColor = vec4(color.rgb, color.a * edgeAlpha);
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

    // MARK: - 增加/减少槽位动画

    func addFullSlot(color: SKColor, duration: TimeInterval = 0.8) {
        // 1. 严格检查：如果已经满了，或者正在动画，直接返回
        guard currentSlots < maxSlots, !isAnimating else { return }
        isAnimating = true

        let startP = currentPercent

        // --- 修复数组越界的关键点 ---
        if currentSlots < slotColors.count {
            // 如果数组已经预留了空间（比如初始化时填了 .clear）
            slotColors[currentSlots] = color
        } else {
            // 如果数组长度不够，则添加新元素
            slotColors.append(color)
        }

        currentSlots += 1
        let targetP = currentPercent

        // 更新纹理
        updatePalette()

        // 2. 执行动画
        let fillAction = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            let t = min(elapsedTime / CGFloat(duration), 1.0) // 确保 t 不超过 1.0
            self?.percentUniform.floatValue = Float(startP + (targetP - startP) * t)
        }

        run(SKAction.sequence([
            fillAction,
            SKAction.run { [weak self] in
                self?.isAnimating = false
            }
        ]))
    }

    /// 核心改动：pourSlot 现在接收 targetBottle 对象，而不是死板的 targetY
    func pourInto(targetBottle: LiquidBottleNode, duration: TimeInterval = 0.8) {
        guard currentSlots > 0, !isAnimating else { return }
        isAnimating = true

        let startP = currentPercent
        let nextSlots = currentSlots - 1
        let targetP = CGFloat(nextSlots) / CGFloat(maxSlots)
        let topColor = getCurrentTopColor()

        // 1. 倾斜
        let tiltAction = SKAction.customAction(withDuration: 0.3) { [weak self] _, elapsedTime in
            let t = elapsedTime / 0.3
            let rot = (.pi / 2) * t
            self?.zRotation = rot
            self?.rotationUniform.floatValue = Float(rot)
        }

        // 2. 倒出（动态计算 targetY）
        let draining = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            let t = elapsedTime / CGFloat(duration)
            self?.percentUniform.floatValue = Float(startP - (startP - targetP) * t)

            // 每一帧都获取目标瓶子最新的液面高度
            // 这样当目标瓶水位上涨时，粒子消失点也会跟着上移
            let currentSurfaceY = targetBottle.getLiquidSurfaceY()
            self?.updatePourParticle(color: topColor, targetY: currentSurfaceY)
        }

        // 3. 回正
        let resetAction = SKAction.customAction(withDuration: 0.3) { [weak self] _, elapsedTime in
            let t = 1.0 - (elapsedTime / 0.3)
            let rot = (.pi / 2) * t
            self?.zRotation = rot
            self?.rotationUniform.floatValue = Float(rot)
        }

        run(SKAction.sequence([
            tiltAction,
            SKAction.group([
                draining,
                SKAction.run { targetBottle.addFullSlot(color: topColor, duration: duration) }
            ]),
            SKAction.run { [weak self] in
                self?.stopPourParticle()
                self?.currentSlots = nextSlots
                if nextSlots < (self?.slotColors.count ?? 0) {
                    self?.slotColors[nextSlots] = .clear
                    self?.updatePalette()
                }
            },
            resetAction,
            SKAction.run { [weak self] in self?.isAnimating = false }
        ]))
    }

    // MARK: - 粒子系统逻辑

    private func updatePourParticle(color: UIColor, targetY: CGFloat) {
        guard let parentNode = parent else { return }

        // 如果粒子发射器不存在，则创建
        if pourEmitter == nil {
            let emitter = SKEmitterNode()
            emitter.particleTexture = createCircleTexture(radius: 7, color: .white)
            emitter.particleBirthRate = 60
            emitter.yAcceleration = -1800
            emitter.particleSpeed = 150
            emitter.particleColor = color
            emitter.particleColorBlendFactor = 1.0
            emitter.particleScale = 0.5
            emitter.particleScaleSpeed = -0.2
            emitter.zPosition = zPosition + 1
            emitter.targetNode = parentNode
            parentNode.addChild(emitter)
            pourEmitter = emitter
        }

        guard let emitter = pourEmitter else { return }

        // 计算起点（瓶口）
        let mouthRadius: CGFloat = 16
        let offsetX = (zRotation > 0) ? -mouthRadius : mouthRadius
        let startPoint = convert(CGPoint(x: offsetX, y: (bottleHeight / 2) - 5), to: parentNode)

        // 动态更新位置
        emitter.position = startPoint
        emitter.emissionAngle = (zRotation > 0) ? .pi : 0

        // 动态计算生命周期：掉落到当前液面的时间
        let dropDistance = abs(startPoint.y - targetY)
        let gravity = abs(emitter.yAcceleration)
        let calculatedLifetime = sqrt(2.0 * dropDistance / gravity) * 0.98

        emitter.particleLifetime = max(0.05, calculatedLifetime)
        emitter.particleAlphaSpeed = -1.0 / emitter.particleLifetime
    }

    private func stopPourParticle() {
        guard let emitter = pourEmitter else { return }
        emitter.particleBirthRate = 0
        let wait = SKAction.wait(forDuration: emitter.particleLifetime + 0.1)
        emitter.run(SKAction.sequence([wait, SKAction.removeFromParent()]))
        pourEmitter = nil
    }

    // MARK: - 辅助方法

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
            let rect = CGRect(x: 0, y: size.height - CGFloat(i + 1) * slotH, width: 1, height: slotH)
            context.fill(rect)
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return SKTexture(image: image!)
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
        let index = currentSlots - 1
        return (index >= 0 && index < slotColors.count) ? slotColors[index] : .white
    }
}
