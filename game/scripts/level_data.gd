class_name StarportLevelData
extends RefCounted
## First-level layout only. Player/enemy combat parameters remain in their existing scripts.
## Relay time ranges are unverified design hypotheses. Aggregate duration awaits a human full run.

const FLOOR: float = 574.0
const WORLD_END: float = 13600.0
const START_X: float = 210.0
const NPC_X: float = 8080.0
const CHECKPOINT_X: float = 8200.0
const CHECKPOINT_COMPLETED_ZONES = [0, 1, 2, 3]
const BOSS_ZONE_INDEX: int = 6
const EXIT_X: float = 13480.0
const FIRST_PLAY_TARGET_SECONDS = Vector2(360.0, 480.0)
const PACING_TARGET_VERIFIED: bool = false
const MEASURED_PRE_RELAY_CHECKPOINT_SECONDS: float = 79.0
const CHECKPOINT_RELAY_IDS = [0, 1]
const RELAY_INTERACT_X: float = 54.0
const RELAY_INTERACT_Y: float = 28.0

## These are ADDITIONAL collision/render rectangles; retain OBSTACLES as well.
## Existing cargo blocks at 2150/2350, 5830 and 11770 are the entry steps.
## Every overlapping upper/lower surface leaves >=96 px standing headroom.
const RELAY_PLATFORMS = [
	Rect2(2010.0, 448.0, 90.0, 18.0),
	Rect2(2150.0, 368.0, 130.0, 18.0),
	Rect2(2300.0, 288.0, 130.0, 18.0),
	Rect2(5680.0, 432.0, 100.0, 18.0),
	Rect2(5830.0, 352.0, 130.0, 18.0),
	Rect2(5680.0, 272.0, 130.0, 18.0),
	Rect2(5980.0, 272.0, 130.0, 18.0),
	Rect2(11615.0, 450.0, 105.0, 18.0),
	Rect2(11765.0, 370.0, 130.0, 18.0),
	Rect2(11615.0, 290.0, 130.0, 18.0),
	Rect2(11765.0, 230.0, 130.0, 18.0),
]

## A gate opens immediately after its two terminals have been activated, in
## either order. Check feet proximity in BOTH axes and require is_on_floor().
## No timer, inventory, extra health, extra waves or movement changes are needed.
const RELAY_STATIONS = [
	{
		"id": 0, "after_zone": 0, "start": 1940.0, "gate_x": 2500.0,
		"name": "货运供电", "hint": "沿发光电缆跳上货架，按 E 接通两处电源，开启前方货闸。",
		"platform_indices": [0, 1, 2],
		"platforms": [RELAY_PLATFORMS[0], RELAY_PLATFORMS[1], RELAY_PLATFORMS[2]],
		"switches": [
			{"id": 0, "feet": Vector2(2215.0, 368.0), "label": "货运电源 A"},
			{"id": 1, "feet": Vector2(2365.0, 288.0), "label": "货运电源 B"},
		],
		"route_feet": [Vector2(2198.0, 528.0), Vector2(2055.0, 448.0), Vector2(2215.0, 368.0), Vector2(2365.0, 288.0)],
		"qa_waypoints": [Vector2(2198.0, 528.0), Vector2(2055.0, 448.0), Vector2(2215.0, 368.0), Vector2(2365.0, 288.0)],
		"first_play_seconds": Vector2(20.0, 35.0), "skilled_seconds": Vector2(8.0, 14.0),
	},
	{
		"id": 1, "after_zone": 2, "start": 5620.0, "gate_x": 6140.0,
		"name": "信号分流", "hint": "中央货箱通向左右两处信号端。任选顺序接通，再沿地面通过货桥。",
		"platform_indices": [3, 4, 5, 6],
		"platforms": [RELAY_PLATFORMS[3], RELAY_PLATFORMS[4], RELAY_PLATFORMS[5], RELAY_PLATFORMS[6]],
		"switches": [
			{"id": 0, "feet": Vector2(5745.0, 272.0), "label": "西侧信号端"},
			{"id": 1, "feet": Vector2(6045.0, 272.0), "label": "东侧信号端"},
		],
		"route_feet": [Vector2(5893.0, 512.0), Vector2(5730.0, 432.0), Vector2(5895.0, 352.0), Vector2(5745.0, 272.0), Vector2(5895.0, 352.0), Vector2(6045.0, 272.0)],
		"qa_waypoints": [Vector2(5893.0, 512.0), Vector2(5730.0, 432.0), Vector2(5895.0, 352.0), Vector2(5745.0, 272.0), Vector2(5895.0, 352.0), Vector2(6045.0, 272.0)],
		"first_play_seconds": Vector2(25.0, 40.0), "skilled_seconds": Vector2(10.0, 16.0),
	},
	{
		"id": 2, "after_zone": 5, "start": 11580.0, "gate_x": 11970.0,
		"name": "核心联锁", "hint": "沿折返检修梯上行，解除高处两道联锁。接通后下落安全，核心门即刻开放。",
		"platform_indices": [7, 8, 9, 10],
		"platforms": [RELAY_PLATFORMS[7], RELAY_PLATFORMS[8], RELAY_PLATFORMS[9], RELAY_PLATFORMS[10]],
		"switches": [
			{"id": 0, "feet": Vector2(11680.0, 290.0), "label": "核心联锁 A"},
			{"id": 1, "feet": Vector2(11830.0, 230.0), "label": "核心联锁 B"},
		],
		"route_feet": [Vector2(11820.0, 530.0), Vector2(11670.0, 450.0), Vector2(11830.0, 370.0), Vector2(11680.0, 290.0), Vector2(11830.0, 230.0)],
		"qa_waypoints": [Vector2(11820.0, 530.0), Vector2(11670.0, 450.0), Vector2(11830.0, 370.0), Vector2(11680.0, 290.0), Vector2(11830.0, 230.0)],
		"first_play_seconds": Vector2(20.0, 35.0), "skilled_seconds": Vector2(10.0, 16.0),
	},
]

## Obstacles occur only between sealed arenas. No required ground enemy needs to jump.
## Three thin, raised maintenance platforms form an optional upper route. Their
## lowest underside is 98 px above the floor, clearing the 96 px player capsule.
const OBSTACLES = [
	Rect2(375.0, 538.0, 84.0, 36.0),
	Rect2(2150.0, 528.0, 96.0, 46.0),
	Rect2(2350.0, 508.0, 136.0, 66.0),
	Rect2(3970.0, 522.0, 110.0, 52.0),
	Rect2(5830.0, 512.0, 126.0, 62.0),
	Rect2(7650.0, 470.0, 140.0, 6.0),
	Rect2(7850.0, 390.0, 190.0, 18.0),
	Rect2(8100.0, 470.0, 160.0, 6.0),
	Rect2(9980.0, 526.0, 100.0, 48.0),
	Rect2(11770.0, 530.0, 100.0, 44.0),
]
const OPTIONAL_ROUTE = {
	"start": 7580.0, "end": 8320.0, "name": "维修栈桥 · 可选上层通路",
	"platform_indices": [5, 6, 7], "ground_route_open": true,
	"hint": "上层栈桥可跳跃探索；沿地面也能抵达维修站。",
}
const CHECKPOINT = {
	"npc_x": NPC_X, "spawn_x": CHECKPOINT_X,
	"completed_zones": CHECKPOINT_COMPLETED_ZONES,
	"name": "维修站 / 米米", "interaction_radius": 160.0,
	"hint": "按 E 维修并保存。前方是双盾防线、混编警戒与中继守卫。",
}

## Existing spawn contract: [{start,left,right,name,waves:[[[kind,x],...],...]}].
## Extra intent/hint fields are optional presentation and QA metadata.
const ENCOUNTERS = [
	{
		"start": 870.0, "left": 700.0, "right": 1920.0,
		"name": "01 / 入港校准", "intent": "先单挑辨认起手，再处理错位双机兵。",
		"hint": "J 连击 · L / Shift 闪避。敌人亮起预警后再判断出手。",
		"waves": [[["melee", 1260.0]], [["melee", 1110.0], ["melee", 1660.0]]],
	},
	{
		"start": 2710.0, "left": 2550.0, "right": 3760.0,
		"name": "02 / 货运分流", "intent": "近战掩护盾兵，清理后首次引入远程干扰。",
		"hint": "K 重击破盾；无人机出手前有预警，接近后优先处理。",
		"waves": [[["melee", 2980.0], ["shield", 3380.0]], [["melee", 2820.0], ["drone", 3490.0]]],
	},
	{
		"start": 4470.0, "left": 4300.0, "right": 5600.0,
		"name": "03 / 信号侧廊", "intent": "三兵种前后分布；后续单无人机让玩家练习追击而非站桩。",
		"hint": "观察射击方向，闪过近战后选择优先目标。U 技能可打穿一条线。",
		"waves": [[["melee", 4780.0], ["shield", 5070.0], ["drone", 5440.0]], [["drone", 4520.0]]],
	},
	{
		"start": 6370.0, "left": 6190.0, "right": 7530.0,
		"name": "04 / 装卸回廊", "intent": "先快后慢；第二波的近战侧翼迫使玩家转向，而不是复制第一波。",
		"hint": "新一波会从不同方向进入，留出闪避空间。清理后前往维修站。",
		"waves": [[["melee", 6800.0], ["drone", 7290.0]], [["melee", 6420.0], ["shield", 6980.0], ["drone", 7320.0]]],
	},
	{
		"start": 8660.0, "left": 8480.0, "right": 9780.0,
		"name": "05 / 双盾防线", "intent": "双盾纵深保护无人机；破口后用轻敌波改变节奏。",
		"hint": "双盾防线可逐个破甲，也可闪过前排切入后方。",
		"waves": [[["shield", 9060.0], ["shield", 9430.0], ["drone", 9620.0]], [["melee", 8710.0], ["drone", 9460.0]]],
	},
	{
		"start": 10380.0, "left": 10200.0, "right": 11560.0,
		"name": "06 / 中继警戒", "intent": "先双近战追击，再一次四敌混编检验破盾、转向和远程优先级。",
		"hint": "这是首领前最后一道防线。利用敌人恢复空档，避免被夹在中央。",
		"waves": [[["melee", 10700.0], ["melee", 11030.0], ["drone", 11380.0]], [["melee", 10310.0], ["shield", 10770.0], ["shield", 11210.0], ["drone", 11410.0]]],
	},
	{
		"start": 12220.0, "left": 12010.0, "right": 13530.0,
		"name": "07 / 中继核心", "intent": "独立首领决斗；横扫、冲撞、震波与半血变招形成最终检验。",
		"hint": "观察首领预警：闪过横扫与冲撞，跳过地面震波，再趁恢复反击。",
		"waves": [[["boss", 13020.0]]],
	},
]

const TRAVERSAL_BEATS = [
	{"start": START_X, "end": 870.0, "name": "降落区 / 操作熟悉"},
	{"start": 1920.0, "end": 2710.0, "name": "货运供电 / 高处双电源"},
	{"start": 3760.0, "end": 4470.0, "name": "观景短廊"},
	{"start": 5600.0, "end": 6370.0, "name": "信号分流 / 左右双端口"},
	{"start": 7530.0, "end": 8660.0, "name": "可选上层栈桥 / 维修检查点"},
	{"start": 9780.0, "end": 10380.0, "name": "警戒通路"},
	{"start": 11560.0, "end": 12220.0, "name": "核心联锁 / 折返检修梯"},
]

static func zones() -> Array:
	return ENCOUNTERS.duplicate(true)

static func regular_enemy_count() -> int:
	var result: int = 0
	for zone in ENCOUNTERS:
		for wave in zone.waves:
			for entry in wave:
				if entry[0] != "boss": result += 1
	return result

