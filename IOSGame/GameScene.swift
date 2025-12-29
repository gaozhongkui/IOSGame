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
    
    // 关键 Uniform：同步液体物理高度与 Shader 采样坐标
    private let percentUniform = SKUniform(name: "u_percent", float: 0.0)
    
    override func didMove(to view: SKView) {
        backgroundColor = .darkGray
        
        // 创建并放置瓶子
        let bottleNode = createFilledBottle()
        bottleNode.position = CGPoint(x: frame.midX, y: frame.midY)
        addChild(bottleNode)
    }
    
    private func createFilledBottle() -> SKNode {
        let container = SKNode()
        
        // 1. 基础纹理与尺寸
        let bottleTexture = SKTexture(imageNamed: "bottle")
        let bottleWidth = (bottleTexture.size().width * bottleHeight) / bottleTexture.size().height
        let bottleSize = CGSize(width: bottleWidth, height: bottleHeight)
        
        // 2. 遮罩设置
        let cropNode = SKCropNode()
        let mask = SKSpriteNode(texture: bottleTexture)
        mask.size = bottleSize
        cropNode.maskNode = mask
        
        // 3. 生成平滑的 8 色渐变纹理
        let paletteTexture = createSmoothPaletteTexture()
        
        // 4. 配置液体节点与 Shader
        let liquidNode = SKSpriteNode(color: .white, size: bottleSize)
        
        let shaderSource = """
        void main() {
            vec2 uv = v_tex_coord;
            float time = u_time * 2.5;
            
            // 水波纹
            float wave = sin(uv.x * 7.0 + time) * 0.008;
            float surfaceLine = 0.98 + wave; 
            if (uv.y > surfaceLine) discard;

            // 绝对颜色采样：此时 u_percent 会随动画从 0.625 平滑变到 0.75
            float absoluteY = uv.y * u_percent;
            vec4 color = texture2D(u_palette, vec2(0.5, absoluteY));
            
            if (uv.y > surfaceLine - 0.015) {
                color.rgb += 0.12;
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
        
        // 5. 瓶子外框（半透明覆盖）
        let bottleBorder = SKSpriteNode(texture: bottleTexture)
        bottleBorder.size = bottleSize
        bottleBorder.zPosition = 10
        bottleBorder.alpha = 0.4
        
        cropNode.addChild(liquidNode)
        container.addChild(cropNode)
        container.addChild(bottleBorder)
        
        return container
    }

    // 生成一张包含 8 种颜色、具备平滑过渡的线性纹理
    private func createSmoothPaletteTexture() -> SKTexture {
        let colors: [UIColor] = [
            .systemBlue, .systemCyan, .systemTeal, .systemGreen,
            .systemYellow, .systemOrange, .systemRed, .systemPurple
        ]
        
        // 渲染高度设为 256 确保色彩插值足够细腻
        let size = CGSize(width: 1, height: 256)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else { return SKTexture() }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let cgColors = colors.map { $0.cgColor } as CFArray
        
        // 均匀分布 8 个颜色的位置 [0.0, 0.14, 0.28 ... 1.0]
        let locations: [CGFloat] = (0..<colors.count).map { CGFloat($0) / CGFloat(colors.count - 1) }
        
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: locations) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: 0, y: size.height),
                                       options: [])
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        let texture = SKTexture(image: image!)
        texture.filteringMode = .linear // 开启线性过滤，解决“僵硬”闪变的关键
        return texture
    }
    
    func fill(to targetPercent: CGFloat) {
        guard let liquid = liquid else { return }
        
        let startPercent = CGFloat(percentUniform.floatValue)
        let duration: TimeInterval = 0.8
        
        // 1. 创建一个自定义 Action，让 Uniform 和高度同步平滑变化
        let syncAction = SKAction.customAction(withDuration: duration) { node, elapsedTime in
            // 计算当前进度比例 (0.0 ~ 1.0)
            let t = elapsedTime / CGFloat(duration)
            
            // 使用线性插值计算当前瞬间的百分比
            let currentP = startPercent + (targetPercent - startPercent) * t
            
            // --- 核心同步点 ---
            // A. 实时更新 Shader 的采样坐标
            self.percentUniform.floatValue = Float(currentP)
            
            // B. 实时更新液体的物理高度
            let currentHeight = self.bottleHeight * currentP
            (node as? SKSpriteNode)?.size.height = currentHeight
        }
        
        syncAction.timingMode = .easeInEaseOut
        liquid.run(syncAction)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // 每次点击增加 12.5% (即 1/8)
        currentPercent += 0.125
        if currentPercent > 1.001 { currentPercent = 0 }
        
        fill(to: currentPercent)
    }
}
