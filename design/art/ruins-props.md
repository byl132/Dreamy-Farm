# 遗迹道具 / 装饰视觉规格（ruins-props）

> **文档类型**：美术圣经配套 · 遗迹场景道具落地规格
> **作者**：林绘澄（美术方向 / art-director）v1.0
> **配套**：`scripts/gameplay/ExploreManager.lua`（Fallbacks / 材质助手 / `RUINS_MAX_DECOR_LIGHTS`）
> **硬约束**：① 怪物本轮**不动**；② 道具视觉权重**不得抢怪物**；③ 自发光必须 `Clone` 基底；④ 点光受 `RUINS_MAX_DECOR_LIGHTS=6` 守卫，超限只自发光不点灯。

## 0. 落地判定基线（代码范式）
所有道具走 **uuid:// 云模型优先 + 本地图元兜底** 双轨：
```lua
if not ExploreTryStatic(node, "uuid://<modelId>", "uuid://<matId>", { castShadows = true }) then
    Fallbacks.<prop>(node)
end
```
| 助手 | 用途 / 约束 |
|---|---|
| `ExploreSafeMaterial(color)` | 移动端安全 lit 材质，按色缓存；改色不污染 |
| `ExploreEmissiveMat(color, glow)` | 自发光材质：内部已 `base:Clone()` + `MatEmissiveColor`；禁止直接对 `ExploreSafeMaterial` 返回值 `SetShaderParameter` |
| `ExploreTryStatic(parent, uuidModel, uuidMat, opts)` | 试 uuid 静态模型，失败返回 `nil` → 调用方兜底 |
| `ExploreCylLimb(parent, name, pos, dims, mat, longAxis, explicitR)` | 圆柱倒角肢体（去 90° 锐边） |
| `RuinsTryAddDecorLight()` | 占 1 盏点光预算（上限 6）；返回 `false` → 只自发光不点灯 |

**几何体拼装铁律**：圆角倒角、柔边、禁硬黑描边；与农场 PBR 圆润化同语。

## 1. 遗迹调色板（Ruins Palette · 固化 token）
| Token | Hex | Color(0–1) | 角色 |
|---|---|---|---|
| `ruin_stone` | `#5A5246` | `Color(0.353, 0.322, 0.275, 1)` | 冷石材主色 |
| `ruin_stone_dark` | `#3F3A32` | `Color(0.247, 0.227, 0.196, 1)` | 石材暗部 / 破损面 |
| `ruin_stone_light` | `#7A7164` | `Color(0.478, 0.443, 0.392, 1)` | 石材高光面 |
| `rune_cyan` | `#5EE0D1` | `Color(0.37, 0.88, 0.82, 1)` | 青色符文（自发光唯一主色） |
| `torch_warm` | `#FF8C1A` | `Color(1.0, 0.55, 0.10, 1)` | 火焰外焰 |
| `torch_warm_core` | `#FFD934` | `Color(1.0, 0.85, 0.20, 1)` | 火焰内焰 |
| `ruins_fill` | — | `Color(0.55, 0.62, 0.72, 1)` | 环境兜底冷灰点光（不计入 6 预算） |

> **禁用**：刺眼高饱和（荧光青/纯红/纯紫）、硬黑描边。所有色锁定在低饱和冷石家族，暖色仅限火焰/点光。

## 2. 点光预算守卫（与 `ExploreManager` 共用 6 盏）
`RUINS_MAX_DECOR_LIGHTS = 6` 由 `RuinsTryAddDecorLight()` 守卫，火炬 / 火盆 / 长明灯 / 晶体锚点 / 出口水晶共享同一池（fill 环境光固定不计入）。
**分配建议**：优先给路径型真点光（火盆/长明灯占 2–4 盏）；火盆多了就少挂墙炬。超出 6 盏的物体仍画暖橙自发光球（`ExploreEmissiveMat(torch_warm, ~1.5)`），**不创建 `Light`**。

## 3. 逐道具规格
### 3.1 石柱（Stone Pillar）
高 2.2–2.8m（高于墙 2.5m，作竖向锚）；半径 0.28–0.40m；柱础略放大。**不占点光**；可选青符文环带 `ExploreEmissiveMat(rune_cyan, 0.8)` 细环（自发光，不投光）。无暖色。纯竖向剪影，与怪物零混淆。本地兜底 `Fallbacks.pillar`（三段递减圆柱 + 盒础/盒头 + 可选青环）。

### 3.2 残破雕像（Broken Statue）
残高 1.4–1.7m（刻意低于玩家，显风化矮小）；宽 0.6–0.9m。**不占点光**；基座一道青符文刻线（自发光 0.8–1.0），无眼状发光。严禁眼状发光点/任何运动/类生物轮廓对称；用"缺肢+歪头+静止"与怪物区分。本地兜底 `Fallbacks.statue`（盒躯干 + 偏移球头 + 残臂 + 断口暗石）。

### 3.3 石棺（Sarcophagus）
长 2.0–2.4m、宽 0.7–0.9m、高 0.55–0.7m；水平质量感。**不占点光**；盖顶青符文腰线自发光 1.0；可开棺时加 `GoldGlow` 地面微光（不投光）。本地兜底 `Fallbacks.sarcophagus`（盒棺体 + 盒盖 + 两端圆柱收头 + 盖顶青符文细条）。

### 3.4 可砸陶罐（Breakable Pot）
高 0.45–0.65m、半径 0.22–0.32m（读作小物）。风化陶土 `Color(0.50,0.42,0.35,1)`；裂纹处一点青符文微光 `rune_cyan`（自发光，暗示可交互）。**不占点光**。碎裂 FX：3–5 个小盒/球按随机速度抛出 + 重力，0.6s 消失；移动端上限 4。本地兜底 `Fallbacks.pot`（压扁球 + 小圆柱颈 + 青符文裂纹）。

### 3.5 符文石碑 / 铭文（Rune Stele / Inscription）
石碑高 1.5–2.0m、宽 0.35–0.45m、厚 0.18–0.25m；墙面铭文 0.6×0.4m 平贴。**"青符文"视觉身份旗舰载体**。**不占点光**（纯自发光）。石碑正面青符文 = `ExploreEmissiveMat(rune_cyan, 1.4)`；铭文 = 平贴自发光面片。与怪物区分：符文在平面/静态/慢呼吸，怪物眼是浮空小球+运动。本地兜底 `Fallbacks.stele`（盒石碑 + 正面自发光符文面 + 顶部慢呼吸）。

### 3.6 火盆 / 长明灯（Fire Brazier / Eternal Flame）
总高 1.0–1.4m；盆半径 0.28–0.35m；明显矮于墙，作近地暖标。盆体 `ruin_stone_dark`；火焰外焰 `torch_warm` + 内焰 `torch_warm_core`。**占点光预算**（同火炬写法）：`RuinsTryAddDecorLight()` → `LIGHT_POINT` range 5.0 / color(1,0.6,0.2) / brightness 1.2 / castShadows false；超限只自发光不点灯。火焰球 `ExploreEmissiveMat(torch_warm, 1.5)` + 内焰。火焰跳动：update 里对火焰球做 `scale` 微抖动（±0.05，0.3s 周期）；尊重 reduced-motion。本地兜底 `Fallbacks.brazier`（圆柱基座 + 盆 + 双层火焰球 + 点光）。

## 4. 落地校验清单（Handoff → 工程）
- [ ] 所有自发光走 `ExploreEmissiveMat`（内部 Clone 基底）；**禁止**对 `ExploreSafeMaterial` 返回值直接 `SetShaderParameter("MatEmissiveColor")`。
- [ ] 实体创建统一 `ExploreTryStatic(uuidModel, uuidMat) or Fallbacks.<prop>` 双轨。
- [ ] 火盆/长明灯/墙炬/晶体锚点 **全部** 经 `RuinsTryAddDecorLight()` 守卫；单房 ≤6 盏点光，超限只自发光。
- [ ] 道具尺度与玩家(1.8m)/墙(2.5m)协调。
- [ ] **无怪物混淆**：道具禁眼状发光、禁类生物对称轮廓、禁运动（除火焰/符文呼吸，且呼吸可被 reduced-motion 关）。
- [ ] 青符文只承载"信息/可交互"语义（石碑/铭文/棺盖/罐裂纹），不浮空成球。
- [ ] 禁用刺眼高饱和；全冷石家族 + 仅火焰暖橙。
- [ ] 与策划 GDD 对齐：可砸陶罐/石棺的开互动作为玩法钩子，视觉仅做"可交互"双编码提示。
