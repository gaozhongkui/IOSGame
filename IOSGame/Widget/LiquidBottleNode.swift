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
    
    // 状态控制
    private var isAnimating = false
    private var slotColors: [UIColor] = []

    // Uniforms
    private let percentUniform = SKUniform(name: "u_percent", float: 0.0)
    private let rotationUniform = SKUniform(name: "u_rotation", float: 0.0)
    private let slotCountUniform = SKUniform(name: "u_slot_count", float: 8.0)
    
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
        slotColors = Array(repeating: .clear, count: maxSlots)
        updatePalette()
    }

    // MARK: - 初始化瓶子与 Shader
    private func setupBottle(imageName: String) {
        let bottleTexture = SKTexture(imageNamed: imageName)
        let ratio = bottleTexture.size().width / bottleTexture.size().height
        let bottleSize = CGSize(width: bottleHeight * ratio, height: bottleHeight)
        
        let cropNode = SKCropNode()
        cropNode.maskNode = SKSpriteNode(texture: bottleTexture, size: bottleSize)
        
        // 优化后的 Shader：增加了 Smoothstep 抗锯齿边缘
        let shaderSource = """
        void main() {
            vec2 uv = v_tex_coord;
            float rot = u_rotation;
            
            float cosR = cos(rot);
            float sinR = sin(rot);
            float rotatedY = (uv.y - 0.5) * cosR + (uv.x - 0.5) * sinR + 0.5;
            
            float wave = sin(uv.x * 7.0 + u_time * 2.5) * 0.005 * cosR;
            float currentLimit = u_percent + wave;
            
            // 使用 smoothstep 消除液面的锯齿感，让边缘更柔和
            float edgeAlpha = smoothstep(currentLimit + 0.003, currentLimit - 0.003, rotatedY);
            if (edgeAlpha <= 0.0) discard;

            float rotFactor = abs(sinR); 
            float samplePos = mix(uv.y, rotatedY / (currentLimit + 0.001), rotFactor);
            samplePos = clamp(samplePos, 0.0, 1.0);
            
            vec4 color = texture2D(u_palette, vec2(0.5, samplePos));
            
            // 刻度线
            float slotBoundary = fract(uv.y * u_slot_count);
            if (slotBoundary < 0.03 || slotBoundary > 0.97) {
                color.rgb *= 0.8;
            }

            // 液面高亮
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
        self.liquid = liquidNode
        
        let bottleBorder = SKSpriteNode(texture: bottleTexture, size: bottleSize)
        bottleBorder.zPosition = 10
        bottleBorder.alpha = 0.4
        
        cropNode.addChild(liquidNode)
        addChild(cropNode)
        addChild(bottleBorder)
    }

    // MARK: - 动画逻辑
    func addFullSlot(color: SKColor, duration: TimeInterval = 0.8) {
        guard currentSlots < maxSlots, !isAnimating else { return }
        isAnimating = true

        let startP = currentPercent
        if currentSlots < slotColors.count {
            slotColors[currentSlots] = color
        } else {
            slotColors.append(color)
        }
        currentSlots += 1
        let targetP = currentPercent
        updatePalette()

        let fillAction = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            let t = elapsedTime / CGFloat(duration)
            self?.percentUniform.floatValue = Float(startP + (targetP - startP) * t)
        }
        
        run(SKAction.sequence([fillAction, SKAction.run { self.isAnimating = false }]))
    }

    func pourSlot(targetY: CGFloat, duration: TimeInterval = 0.8) {
        guard currentSlots > 0, !isAnimating else { return }
        isAnimating = true

        let startP = currentPercent
        let nextSlots = currentSlots - 1
        let targetP = CGFloat(nextSlots) / CGFloat(maxSlots)
        let topColor = getCurrentTopColor()
        let angle: CGFloat = .pi / 2
        
        let tiltAction = SKAction.customAction(withDuration: 0.3) { [weak self] _, elapsedTime in
            let t = elapsedTime / 0.3
            let currentRot = angle * t
            self?.zRotation = currentRot
            self?.rotationUniform.floatValue = Float(currentRot)
        }

        let draining = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            let t = elapsedTime / CGFloat(duration)
            self?.percentUniform.floatValue = Float(startP - (startP - targetP) * t)
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
                SKAction.run { [weak self] in self?.startPourParticle(color: topColor, targetY: targetY) },
                draining
            ]),
            SKAction.run { [weak self] in self?.stopPourParticle() },
            resetAction,
            SKAction.run { [weak self] in
                self?.currentSlots = nextSlots
                if nextSlots < (self?.slotColors.count ?? 0) {
                    self?.slotColors[nextSlots] = .clear
                    self?.updatePalette()
                }
                self?.isAnimating = false
            }
        ]))
    }

    // MARK: - 粒子效果优化
    private func startPourParticle(color: UIColor, targetY: CGFloat) {
        stopPourParticle()
        guard let parentNode = self.parent else { return }
        
        let emitter = SKEmitterNode()
        let gravity: CGFloat = 1800
        emitter.yAcceleration = -gravity
        emitter.particleSpeed = 160
        
        // 发射点偏移逻辑
        let mouthRadius: CGFloat = 16
        let offsetX = (zRotation > 0) ? -mouthRadius : mouthRadius
        let startPointInParent = self.convert(CGPoint(x: offsetX, y: (bottleHeight / 2) - 5), to: parentNode)
        
        // 动态计算精准生命周期
        let dropDistance = abs(startPointInParent.y - targetY)
        let calculatedLifetime = sqrt(2.0 * dropDistance / gravity) * 0.96
        
        emitter.particleLifetime = max(0.1, calculatedLifetime)
        emitter.particleTexture = createCircleTexture(radius: 7, color: .white)
        emitter.particleBirthRate = 50
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1.0
        
        // 视觉：下落时变细，接近目标时透明消失
        emitter.particleScale = 0.5
        emitter.particleScaleSpeed = -0.3
        emitter.particleAlphaSpeed = -1.0 / calculatedLifetime
        
        emitter.emissionAngle = (zRotation > 0) ? .pi : 0
        emitter.emissionAngleRange = 0.08
        emitter.position = startPointInParent
        emitter.targetNode = parentNode
        emitter.zPosition = self.zPosition + 1
        
        parentNode.addChild(emitter)
        pourEmitter = emitter
    }
    
    private func stopPourParticle() {
        guard let emitter = pourEmitter else { return }
        emitter.particleBirthRate = 0
        let wait = SKAction.wait(forDuration: emitter.particleLifetime + 0.1)
        emitter.run(SKAction.sequence([wait, SKAction.removeFromParent()]))
        pourEmitter = nil
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
