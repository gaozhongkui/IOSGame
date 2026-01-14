//
//  GameScene.swift
//  IOSGame
//
//  Created by gaozhongkui on 2025/12/29.
//

import GameplayKit
import SpriteKit

class GameScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .white

        let sprite = SKSpriteNode(imageNamed: "card")
        sprite.size = CGSize(width: 100, height: (sprite.size.height * 100) / sprite.size.width)
        sprite.position = CGPoint(x: frame.midX, y: frame.midY)
        addChild(sprite)

        // GLSL Shader
        let bendShader = SKShader(source: """
        void main() {
            vec2 uv = v_tex_coord;

            // 水平弯曲：根据 y 坐标拉伸 x 坐标
            float bendAmount = 0.3; // 调整弯曲程度
            uv.x += bendAmount * (uv.y - 0.5) * (uv.y - 0.5); // y 越靠近中间弯曲越小

            // 垂直弯曲：根据 x 坐标拉伸 y 坐标
            uv.y += bendAmount * (uv.x - 0.5) * (uv.x - 0.5);

            gl_FragColor = texture2D(u_texture, uv);
        }
        """)

        sprite.shader = bendShader
        
        let bendUniform = SKUniform(name: "u_bendAmount", float: 0.3)
        bendShader.addUniform(bendUniform)
    }
}
