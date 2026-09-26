# PLAN — SPACE SALVAGE (working title)

> **Master dokumen proyek.** Berisi desain game lengkap (GDD v2), struktur folder, roadmap implementasi, dan progress log.
> Sumber desain: `C:\Users\notsomnia\Downloads\GDD_Space_Salvage.md` (v2 — akan terus di-update, plan.md ini ikut di-sync).

Resource Management ala **Stacklands**, tema Astronot/Penjelajah Galaksi Terdampar — Engine: **Godot 4.7** (GDScript, GL Compatibility, 2D).

---

# BAGIAN A — DESAIN GAME (GDD v2, lengkap)

## A0. GLOSARIUM CEPAT

| Istilah | Arti |
|---|---|
| Card | Objek dasar di board, semua "benda" di game ini adalah Card |
| Board | Area drag-and-drop utama tempat semua Card diletakkan |
| Node | Card statis sumber daya mentah (mis. Asteroid Field) — bukan Unit, bukan resource item |
| Unit | Card karakter/pekerja yang bisa di-drag ke Node/Building/Package untuk bekerja |
| Item | Card resource yang bisa ditumpuk (stack) di inventory/board: Raw, Processed, Food, dll |
| Day/Tick | 1 siklus waktu game, dipicu tombol "End Day" |
| Combine | Aksi drag 1 card ke card lain untuk memicu crafting/recipe |

## A1. CORE LOOP

```
[Board State: Node cards, Item cards, Building cards, Unit cards tersebar]
		↓
Player drag Unit → Node/Building/Package  →  Unit mulai kerja (state: Working)
		↓
Player drag Item + Item (atau Item + Building) → cek Recipe table → jika match → spawn Output card
		↓
Player rakit Package (isi requirement) → kirim ke Sektor → dapat Credits + Rep
		↓
Player klik "End Day" → jalankan Tick Resolution (lihat A15) → stat berubah, event random muncul
		↓
Ulangi. Game over jika O2=0 berkepanjangan / semua Unit mati / Hull=0
```

## A1.1 BOARD / PLAYMAT LAYOUT

Playmat adalah **satu board tunggal, dibagi visual jadi 2 zona** (bukan 2 board terpisah, tidak ada loading/switch screen).

```
┌─────────────────────────┬─────────────────────────┐
│   ZONA KAPAL (kiri)      │   ZONA ANGKASA (kanan)   │
│   Ship Interior           │   Open Space / Sector     │
│                           │                           │
│  - Building slot          │  - Node card (gather)     │
│  - Unit idle/assign       │  - Event card muncul di   │
│  - Card Pack opening area │    sini (visual)          │
│  - Package assembly       │  - Titik keberangkatan    │
│    (dekat Cargo Bay)      │    Package ke sektor lain │
└─────────────────────────┴─────────────────────────┘
		↑ garis batas kosmetik (airlock) ↑
   Unit bebas di-drag nyebrang kedua zona kapan saja
```

### Rules

- **Building** hanya bisa ditempatkan/dibangun di **Zona Kapal**.
- **Node** hanya muncul/spawn di **Zona Angkasa**.
- **Unit** bebas dipindah ke zona manapun. Drag Unit dari Zona Kapal → Node di Zona Angkasa = "keluar EVA buat gathering". Drag balik ke Zona Kapal = "masuk kapal lagi". Untuk v1 tidak ada cost tambahan buat nyebrang zona (opsi EVA Suit requirement sebagai penyeimbang ada di A18, belum diputuskan untuk v1).
- **Package** dirakit di Zona Kapal (dekat Building Cargo Bay), lalu "diberangkatkan" dengan drag Unit(role: Pilot lebih baik) + Package ke titik keberangkatan di ujung Zona Angkasa → memicu state TRAVELING (lihat A4, A8).
- **Stat Ship** (O2, Food, Hull, Power) ditampilkan sebagai HUD tetap di atas board (bukan card, bukan milik satu zona) — berlaku global untuk seluruh kapal.
- Zona Angkasa bisa melebar/scroll seiring Node baru ditemukan (progres eksplorasi sektor). Zona Kapal melebar seiring Building baru dibangun (opsional, tuning lanjut — lihat A18).

```gdscript
enum BoardZone { SHIP_INTERIOR, OPEN_SPACE }
# dipakai board manager untuk validasi drop:
#   BuildingCardData → hanya boleh drop di SHIP_INTERIOR
#   NodeCardData      → hanya spawn di OPEN_SPACE
#   UnitCardData      → boleh drop di kedua zona, TAPI lihat A1.2 untuk syarat masuk OPEN_SPACE
```

## A1.2 SISTEM O2 TETHER (EVA Connection)

Setiap Unit yang mau kerja di Zona Angkasa (gather di Node) butuh koneksi oksigen ke kapal — divisualisasikan sebagai **kabel/tether** yang menyambung dari card Unit ke Building **O2 Umbilical Station** di Zona Kapal.

### Rule

- **O2 Umbilical Station** adalah Building (lihat A7) dengan field `max_connections`.
- Saat Unit di-drag dari Zona Kapal ke Zona Angkasa, sistem cek slot kosong di O2 Umbilical Station manapun yang sudah dibangun:
  - Ada slot kosong → Unit jadi **connected** (tether tervisualisasi sebagai garis kabel dari card Unit ke card Station), boleh WORKING normal di Node manapun di Zona Angkasa.
  - Tidak ada slot kosong → drag ditolak, KECUALI Unit itu sedang equip Tool **Portable O2 Tank** (lihat A6).
- Unit connected otomatis **disconnect** (slot kebuka lagi) begitu ditarik balik ke Zona Kapal.
- Kalau Station kehilangan Power (misal event Solar Flare) sementara ada Unit connected → semua Unit yang connected ke Station itu berstatus **O2 Cut** sampai Power nyala lagi atau Unit ditarik balik ke kapal.

### Formula

```
max_units_outside_bersamaan = Σ max_connections(semua O2 Umbilical Station terbangun & berdaya)

on_drag_unit_to_open_space(unit):
	if unit.has_tool("portable_o2_tank"):
		allow, tank_remaining_days -= 1 tiap End Day selagi di luar
	elif units_connected_saat_ini < max_units_outside_bersamaan:
		allow, unit.is_tethered = true
	else:
		reject_drag("butuh slot O2 Umbilical Station kosong")

tiap End Day:
	if unit.is_tethered and station_terkait.has_power() == false:
		unit.status = O2_CUT
	if unit.has_tool("portable_o2_tank") and tank_remaining_days <= 0:
		unit.status = O2_CUT

	if unit.status == O2_CUT:
		# pakai formula kematian yang sama seperti global O2=0 di A14
		25% chance unit → DEAD, tiap hari selama status O2_CUT bertahan

	if unit kembali ke Zona Kapal:
		unit.is_tethered = false
		unit.status = NORMAL
		tank_remaining_days = reset ke default (recharge otomatis saat di kapal)
```

## A2. KATEGORI CARD (Card Type Enum)

```gdscript
enum CardCategory {
	NODE,           # sumber daya mentah statis
	ITEM_RAW,       # resource mentah, stackable
	ITEM_PROCESSED, # resource olahan, stackable
	ITEM_FOOD,      # consumable, stackable
	TOOL,           # equipment, biasanya dipasang ke Unit/dipakai sekali
	BUILDING,       # struktur produksi pasif, tidak bisa dipindah setelah dibangun
	UNIT,           # karakter pekerja, bisa displace/di-drag
	PACKAGE,        # quest delivery card
	EVENT,          # kartu event/threat, muncul otomatis, bukan hasil drag player
	CURRENCY_LOOT,  # Credits, Artifact — hasil jual/reward
}
```

Semua card mewarisi base schema ini:

```gdscript
# CardData.gd — base Resource untuk SEMUA card
class_name CardData extends Resource
@export var id: String              # unique key, mis. "node_asteroid_field"
@export var display_name: String
@export var category: CardCategory
@export var rarity: Rarity          # COMMON, UNCOMMON, RARE, EPIC
@export var icon: Texture2D
@export var description: String
@export var stack_max: int = 99     # khusus ITEM_*, 0 kalau non-stackable
@export var sell_value: int = 0
```

## A3. NODE CARD (sumber daya mentah — statis di board)

Node BUKAN item, BUKAN unit. Node adalah "tempat" yang di-drag Unit ke atasnya untuk memicu gather otomatis berulang (mirip Tree/Rock/Bush di Stacklands).

> **Zona:** Node hanya muncul/spawn di **Zona Angkasa (kanan)** — lihat A1.1.

```gdscript
# NodeCardData.gd extends CardData
@export var output_item_id: String       # id ITEM yang di-spawn tiap panen
@export var gather_interval_sec: float   # base waktu 1x panen (real-time, sesuai Stacklands-style)
@export var output_qty: int = 1
@export var is_limited: bool = false     # true = punya durability (habis), false = infinite
@export var durability: int = 0          # dipakai hanya kalau is_limited = true, berkurang tiap panen
@export var max_unit_slots: int = 1      # berapa Unit bisa kerja bareng di 1 node (percepat linear)
```

### Tabel Node

| Node Card | Output | Interval Dasar | Infinite/Limited | Slot Unit |
|---|---|---|---|---|
| Asteroid Field | Space Ore | 8s | Infinite (tapi ada regen-delay, lihat formula) | 2 |
| Debris Field | Scrap Metal | 5s | Infinite | 2 |
| Ice Field | Ice Chunk | 6s | Limited, durability = 15 | 1 |
| Gas Cloud | Space Gas | 10s | Infinite, **butuh Tool: Cutting Laser terpasang di Unit** sebelum bisa gather | 1 |
| Alien Ruins | Alien Flora / Crystal Ore (50/50) | 12s | Limited, durability = 8 | 1 |

### Formula Gather

```
effective_interval = gather_interval_sec / unit_efficiency
unit_efficiency: Astronaut = 1.0, Engineer_di_node_mining = 1.5, Specialist_lain = 1.0

# tiap effective_interval detik selagi Unit berstatus WORKING di node ini:
spawn_item(output_item_id, output_qty) di slot kosong terdekat pada board

if node.is_limited:
	node.durability -= 1
	if node.durability <= 0:
		remove_node_from_board()   # node hilang, Unit otomatis jadi IDLE

# node infinite tetap boleh diberi "regen-delay" opsional supaya tidak dispam:
regen_delay_after_burst = 0 (default off, bisa dituning kalau perlu balancing lanjutan)
```

Alien Ruins hanya muncul di board lewat: Event `Alien Encounter` (opsi "explore"), atau random spawn saat pindah ke sektor baru.

## A4. UNIT CARD (pekerja, statis-tapi-bisa-dipindah)

Satu kategori Unit dipakai untuk SEMUA jenis pekerja (bukan sub-card berbeda). Unit dibedakan lewat field `role`.

```gdscript
# UnitCardData.gd extends CardData
@export var role: UnitRole   # GENERALIST, ENGINEER, SCIENTIST, PILOT, ROBOT_DRONE
@export var role_efficiency_map: Dictionary  # { "node_asteroid_field": 1.5, "building_smelter": 2.0, ... }
@export var needs_food: bool = true          # false untuk Robot Drone
@export var needs_oxygen: bool = true        # false untuk Robot Drone
@export var needs_power_to_work: bool = false # true untuk Robot Drone
# runtime state (bukan @export, di-track saat gameplay):
var is_tethered: bool = false        # true kalau connected ke O2 Umbilical Station, lihat A1.2
var tether_status: TetherStatus = TetherStatus.NORMAL  # NORMAL, O2_CUT
```

### Unit State Machine

```
enum UnitState { IDLE, WORKING, TRAVELING, DEAD }

IDLE      → default, tergeletak bebas di board, bisa di-drag kemanapun
WORKING   → sedang ditempel ke Node / Building / assemble Package, jalankan gather/produksi loop
TRAVELING → sedang membawa Package ke sektor tujuan (tidak bisa dipakai sampai sampai tujuan)
DEAD      → dihapus dari board, tidak bisa dipakai lagi

Transisi:
  drag Unit ke Node/Building/Package     → IDLE atau WORKING → WORKING (di target baru)
  drag Unit menjauh dari target          → WORKING → IDLE
  assign Unit sebagai Pilot pengantar    → WORKING/IDLE → TRAVELING, otomatis balik IDLE setelah travel_days selesai
  O2/Food = 0 berkepanjangan (lihat A14) → WORKING/IDLE → DEAD
```

Recruit Unit baru lewat **Recruit Pack** (lihat A12) atau event rescue.

### A4a. PROMOSI ROLE (keputusan v2.1)

Semua Unit yang direkrut **selalu mulai sebagai Astronaut (GENERALIST)**. Role spesialis (Engineer/Scientist/Pilot) didapat dengan **promosi**: drag (combine) kartu Astronaut + item tertentu → kartu berubah jadi role baru (posisi tetap di board, konsumsi item).

| Promosi | Combine (input) | Syarat | Output |
|---|---|---|---|
| Engineer | Astronaut ×1 + Circuit Board ×2 | Workshop terbangun | Engineer ×1 |
| Scientist | Astronaut ×1 + Alien Flora ×1 | Workshop terbangun | Scientist ×1 |
| Pilot | Astronaut ×1 + Fuel Cell ×2 | Workshop terbangun | Pilot ×1 |

- Robot Drone **bukan** promosi — tetap di-craft langsung dari item (Circuit Board ×3 + Metal Ingot ×2).
- Data: 3 resep promosi (`recipe_promote_engineer|scientist|pilot`) dengan `required_building_id = "building_workshop"`, durasi instan. Diproses oleh Combine Engine (A13) sama seperti resep biasa.
- Jika promosi di-revert/putus (belum diputuskan, open question), lihat Bagian E.

## A5. ITEM CARD (Raw / Processed / Food) — stackable, hasil gather/craft

```gdscript
# ItemCardData.gd extends CardData
@export var item_type: ItemType   # RAW, PROCESSED, FOOD
@export var food_restore: int = 0 # khusus FOOD
```

### A5a. Raw Resource (hasil panen Node, lihat A3 untuk sumbernya)

| Item | Sumber Node | Rarity |
|---|---|---|
| Space Ore | Asteroid Field | Common |
| Scrap Metal | Debris Field | Common |
| Ice Chunk | Ice Field | Common |
| Space Gas | Gas Cloud | Uncommon |
| Alien Flora | Alien Ruins | Rare |
| Crystal Ore | Alien Ruins | Epic |
| Meteorite Fragment | (bukan node — drop dari Event "Meteor Shower") | Rare |

### A5b. Processed Resource (hasil Combine 2 Item, atau produksi pasif Building)

| Output | Resep (Combine) | Cara Alternatif (pasif) |
|---|---|---|
| Water | Ice Chunk ke Structure Furnace / Little Furnace | – |
| Oxygen Canister | Water + Power (otomatis, syarat Building = Oxygen Generator berdiri & ada Unit WORKING di situ) | pasif harian |
| Metal Ingot | Space Ore ×2 (drag stack ke stack) | pasif via Smelter + Unit WORKING |
| Fuel Cell | Space Gas ×2 | pasif via Fuel Refinery + Unit WORKING |
| Circuit Board | Scrap Metal ×2 + Crystal Ore ×1 | manual combine saja |
| Alien Extract | Alien Flora ×1 | pasif via Science Lab + Scientist WORKING |

### A5c. Food

| Item | Resep/Sumber | Food Restore |
|---|---|---|
| Ration Pack | Loot awal / Salvage Pack | 20 |
| Hydro Veggie | pasif via Hydroponics Bay + Unit WORKING (butuh Water sebagai input harian) | 15 |
| Protein Paste | Alien Extract + "Processor" (Tool) | 25 |
| Feast Meal | Hydro Veggie ×3 + Protein Paste ×1 (butuh Unit role apapun WORKING di Building Kitchen) | 60 (+Morale 10) |

## A6. TOOL CARD

Tool dipasang (equip) ke Unit lewat drag Tool→Unit, atau dipakai sekali habis (consumable) tergantung `is_consumable`.

```gdscript
# ToolCardData.gd extends CardData
@export var effect_type: ToolEffect  # UNLOCK_GATHER, SPEED_BOOST, REPAIR, CRAFT_UNLOCK
@export var effect_value: float
@export var is_consumable: bool = false
```

| Tool | Resep | Efek |
|---|---|---|
| Mining Drill | Scrap Metal ×3 (butuh Engineer WORKING saat combine) | Equip ke Unit → gather di Asteroid Field 2× lebih cepat |
| Scanner | Circuit Board ×1 + Scrap Metal ×2 | Reveal Package tersembunyi / Node tersembunyi di sektor |
| Cutting Laser | Metal Ingot ×2 + Circuit Board ×1 | Equip ke Unit → wajib dipakai sebelum bisa gather Gas Cloud |
| Repair Kit | Scrap Metal ×2 + Welding Torch ×1 | Consumable, pakai ke kartu Ship/Hull → Hull +20 |
| Oxygen Tank | Water + Ice Chunk | Consumable, pakai ke Unit → O2 +25 |

## A7. BUILDING CARD

Building ditempatkan (bukan stackable), butuh Power untuk aktif, dan butuh minimal 1 Unit berstatus WORKING di situ supaya produksi jalan (kecuali disebutkan lain).

> **Zona:** Building hanya bisa ditempatkan di **Zona Kapal (kiri)** — lihat A1.1.

```gdscript
# BuildingCardData.gd extends CardData
@export var build_cost: Array[ItemRequirement]  # [{item_id, qty}, ...]
@export var power_draw: int
@export var max_unit_slots: int = 1
@export var production: ProductionRule   # {input_item_id/qty (opsional), output_item_id, qty, interval_days=1}
@export var passive_effect: String = ""  # untuk building non-produksi (Cargo Bay, Trade Post, dst)
```

| Building | Build Cost | Power Draw | Produksi/Efek per Hari (butuh Unit WORKING) |
|---|---|---|---|
| Hydroponics Bay | Metal Ingot ×3 + Water ×2 | 5 | Water → Hydro Veggie |
| Oxygen Generator | Metal Ingot ×3 + Circuit Board ×1 | 8 | Water → Oxygen Canister → otomatis dipakai isi ulang O2 kapal |
| Smelter | Scrap Metal ×5 | 6 | Space Ore ×2 → Metal Ingot ×1 (otomatis kalau ada stok Ore) |
| Fuel Refinery | Metal Ingot ×4 + Circuit Board ×1 | 6 | Space Gas ×2 → Fuel Cell ×1 |
| Workshop | Metal Ingot ×5 | 4 | Unlock resep Tool tier-2 (tidak produksi item) |
| Science Lab | Metal Ingot ×4 + Crystal Ore ×1 | 10 | Alien Flora ×1 → Alien Extract ×1 |
| Cargo Bay | Scrap Metal ×6 | 0 | Pasif: +50% stack_max semua Item (tidak butuh Unit) |
| Solar Panel | Metal Ingot ×3 | 0 (generator, minus) | Pasif: +Power_generated harian (tidak butuh Unit) |
| Trade Post | Metal Ingot ×5 + Circuit Board ×1 | 3 | Buka fitur "Sell Item" jadi Credits |
| Med Bay | Metal Ingot ×4 + Alien Extract ×1 | 5 | Cegah 1 Unit mati/hari saat O2 atau Food kritis |
| O2 Umbilical Station | Metal Ingot ×4 + Circuit Board ×2 | 6 | Tidak produksi item — pasif: sediakan `max_connections` slot tether O2 buat Unit kerja di Zona Angkasa (lihat A1.2) |

## A8. PACKAGE CARD (quest delivery)

```gdscript
# PackageCardData.gd extends CardData
@export var destination_sector_id: String
@export var required_items: Array[ItemRequirement]
@export var reward_credits: int
@export var reward_rep: int
@export var deadline_days: int
@export var tier: int   # 1-3, pengaruh reward_multiplier
```

Alur:
```
1. Package card muncul di Zona Kapal, dekat Cargo Bay (auto-spawn via Comm Array, atau manual beli di Trade Post)
2. Player drag Item yang sesuai requirement ke Package card → item ter-"lock" ke package (qty berkurang dari stok)
3. Setelah semua requirement terpenuhi → drag Package + 1 Unit (idealnya Pilot) bareng ke titik keberangkatan
   di ujung Zona Angkasa (lihat A1.1) → Unit masuk state TRAVELING
4. Setelah travel_days berlalu (dihitung tiap End Day) → Package selesai:
	 grant reward_credits, reward_rep
	 Unit kembali ke Zona Kapal dengan state IDLE
```

### Formula Reward

```
reward_credits = Σ(sell_value(item) × qty) × delivery_multiplier
delivery_multiplier: Tier1=1.5, Tier2=2.0, Tier3=3.0

reward_rep = base_rep(tier) × timing_bonus
timing_bonus = 1.2 jika selesai ≤ 50% deadline_days
			 = 1.0 jika selesai tepat waktu
			 = 0.5 jika telat (tetap diterima)

travel_days = base_distance(sector_id) / (1 + pilot_bonus)
pilot_bonus = 0.5 jika Unit yang dikirim role == PILOT, else 0
```

### Tabel Sektor

| Sektor | Jarak Dasar (hari) | Rep Required Unlock | Reward Multiplier |
|---|---|---|---|
| Debris Field (starting) | 1 | 0 | 1.0 |
| Asteroid Belt | 2 | 20 | 1.5 |
| Gas Nebula | 3 | 50 | 2.0 |
| Alien Ruins Sector | 4 | 100 | 3.0 |
| Deep Void | 6 | 200 | 4.5 |

## A9. EVENT CARD (muncul otomatis, bukan hasil combine player)

```gdscript
# EventCardData.gd extends CardData
@export var effect_type: EventEffect  # DAMAGE_HULL, DAMAGE_O2, STEAL_RESOURCE, POWER_DEBUFF, BUFF_LOOT, PLAYER_CHOICE
@export var effect_value: float
@export var duration_days: int = 0     # 0 = instan, >0 = efek berlangsung X hari
@export var choices: Array[EventChoice] = []  # khusus PLAYER_CHOICE
```

| Event | Efek | Mitigasi |
|---|---|---|
| Asteroid Storm | Hull -15 instan | Repair Kit siap pakai |
| Space Pirates | Curi 20% dari salah satu stack Item random | Defense Turret (building lanjutan, belum masuk v1) |
| Meteor Shower | Spawn Meteorite Fragment ×3 di board (positif) | – |
| Alien Encounter | Player pilih: **Trade** (dapat Alien Pack gratis) / **Flee** (aman, no reward) | Keputusan manual |

### Formula Kemunculan Event

```
P(event_muncul, hari ke-d) = clamp(0.15 + 0.01 × d, 0.15, 0.6)
event_terpilih = weighted_random(event_pool, weight = rarity_weight)
effect_value_aktual = base_effect_value × event_severity_multiplier(d)   # lihat A14
```

## A10. CURRENCY & SELL

**Credits** — dari reward Package, atau jual Item di Trade Post.
**Reputation (Rep)** — dari reward Package, dipakai unlock sektor baru & tier pack lebih tinggi.

```
sell_value(item) = base_value(item) × rarity_multiplier
rarity_multiplier: Common=1.0, Uncommon=1.5, Rare=2.5, Epic=4.0
```

## A11. SHIP / SURVIVAL STATS

| Stat | Awal | Max | Naik dari | Turun dari |
|---|---|---|---|---|
| Oxygen (O2) | 100 | 100 | Oxygen Canister (auto-consumed saat produksi Oxygen Generator) | Konsumsi harian kru |
| Food/Hunger | 100 | 100 | Makan Food item (auto-consumed End Day) | Konsumsi harian kru |
| Hull Integrity | 100 | 100 | Repair Kit | Event serangan |
| Power | 50 | tergantung total Solar Panel | Solar Panel, Fuel Cell (emergency) | Power_draw semua Building/Tool aktif |
| Morale (fase 2, opsional v1) | 100 | 100 | Feast Meal, event positif | Food/O2 kritis, Unit mati, Hull rusak |

## A12. CARD PACK & EKONOMI

| Pack | Harga Dasar (Credits) | Isi | Drop Table |
|---|---|---|---|
| Salvage Pack | 10 | 3 card | Raw Item 70%, Food 20%, Event ringan 10% |
| Tech Pack | 30 | 3 card | Processed Item 40%, Tool 30%, Circuit Board 20%, Rare item 10% |
| Recruit Pack | 50 | 1 Unit card | Generalist 50%, Engineer 20%, Scientist 20%, Pilot 10% |
| Alien Pack | 80 | 2 card | Alien Flora 40%, Crystal Ore 25%, Alien Extract 15%, Artifact Loot 20% |
| Mystery Pack (reward only, tidak dijual) | – | 1-4 card | Semua tier termasuk Epic |

```
harga_pack(n) = harga_dasar × (1 + 0.05 × n)   # n = jumlah pack tipe sama yang sudah dibeli sepanjang game

weight_total = Σ weight(item_kandidat)
P(item) = weight(item) / weight_total
weight_default: Common=100, Uncommon=45, Rare=15, Epic=5
```

## A13. COMBINE / CRAFTING — RULE ENGINE

Semua resep didefinisikan sebagai data (`.tres`), bukan hardcode, supaya gampang nambah konten.

```gdscript
# CraftRecipe.gd extends Resource
@export var inputs: Array[ItemRequirement]      # bisa Item, atau requirement "Unit dengan role tertentu WORKING"
@export var required_building_id: String = ""   # "" jika manual combine di board
@export var required_unit_role: UnitRole = UnitRole.ANY
@export var output_id: String
@export var output_qty: int = 1
@export var duration_days: int = 0   # 0 = instan (manual combine), >0 = perlu N hari (produksi Building)
```

### Tabel Ringkas Semua Resep (sumber: PDF Combining Recipe — menggantikan tabel lama)

| Input | Building/Unit Prasyarat | Output |
|---|---|---|
| Water + Ice Chunk | – | Oxygen Tank (consumable: +25 O2 saat dipakai ke Unit) |
| Water + Space Rock | – | Dirt |
| Iron + Component | – | Excavation Tools |
| Iron + Iron | – | Component |
| Water + Dirt | – | Fertile Dirt |
| Space Rock ×2 + Iron | – | Furnace |
| Fertile Dirt ×2 + Component | – | Green Room |
| Component ×2 + Dirt | – | Water Collector |
| Energy Cell + Component ×2 | – | Helper Station |
| Mushroom | Structure Furnace / Little Furnace | Food |
| Iron Ore | Structure Furnace / Little Furnace | Iron |
| Ice Chunk | Structure Furnace / Little Furnace | Water |
| Water + Food | Green Room + Astronaut / Little Gardener | Mushroom ×2 |
| Water + Mushroom | Green Room + Astronaut / Little Gardener | Mushroom ×2 |
| Energy Cell + Space Rock + Iron | Helper Station + Astronaut (combine saja) | Little Helper |
| Little Helper + Excavation Tools | – | Little Excavator |
| Little Helper + Dirt | – | Little Gardener |
| Little Helper + Iron + Space Rock ×2 | – | Little Furnace |
| Iron ×2 + Scrap Metal | – | Energy Cell (sumber craftable, beginner) |

Resolusi combine (manual, instan):
```
on_drag_drop(card_a, card_b):
	recipe = find_recipe_matching(card_a, card_b)   # cek dua arah, urutan tidak penting
	if recipe == null: return "no match, cards stay separate"
	if recipe.required_unit_role != ANY and no Unit(role=required_unit_role, state=WORKING nearby):
		return "blocked: butuh Unit role X"
	consume(recipe.inputs)
	spawn(recipe.output_id, recipe.output_qty)
```

## A14. FORMULA KONSUMSI & KEMATIAN

```
O2_consumption/hari    = 5 × jumlah_unit_hidup_yg_needs_oxygen
Food_consumption/hari  = 4 × jumlah_unit_hidup_yg_needs_food
Power_consumption/hari = Σ power_draw(building_aktif) + Σ power_draw(unit ROBOT_DRONE working)

O2_baru    = clamp(O2 - O2_consumption + O2_produced, 0, 100)
Food_baru  = clamp(Food - Food_consumption + Food_produced, 0, 100)
Power_baru = clamp(Power - Power_consumption + Power_generated, 0, Power_cap)

# jika Power_baru akan negatif: auto-shutdown building dengan power_draw tertinggi dulu,
# KECUALI Oxygen Generator & Med Bay (life support diprioritaskan tetap nyala)

if O2 == 0:
	tiap Unit(needs_oxygen=true, alive) punya 25% chance DEAD per hari
if Food == 0:
	Morale -10/hari
	if Food == 0 selama 3 hari berturut-turut: 1 Unit random → DEAD (Med Bay bisa cegah ini, lihat A7)
if Hull == 0:
	GAME OVER
```

## A15. TICK RESOLUTION — PSEUDOCODE "END DAY"

Ini fungsi utama yang dipanggil setiap player klik tombol End Day. Urutan penting untuk konsistensi.

```
func end_day():
	day += 1

	# 1. Resolve semua Building production yang duration_days habis
	for building in active_buildings:
		if building.has_unit_working() and has_power(building):
			resolve_production(building)   # consume input, spawn output sesuai A13

	# 2. Auto-consume Food untuk semua Unit hidup
	consume_food_stock(Food_consumption)

	# 3. Auto-consume/replenish O2 dari Oxygen Canister stock
	replenish_oxygen()

	# 4. Update stat utama sesuai formula A14
	update_stats(O2, Food, Power)

	# 5. Cek kematian/critical state
	resolve_critical_effects()

	# 6. Resolve Package yang sedang TRAVELING (kurangi travel_days_remaining, selesai kalau 0)
	resolve_traveling_packages()

	# 7. Roll random Event sesuai formula A9
	maybe_spawn_event(day)

	# 8. Apply difficulty scaling (lihat A16) ke variabel global
	apply_difficulty_scaling(day)

	# 9. Cek kondisi Game Over
	check_game_over()   # O2 berkepanjangan / semua Unit mati / Hull=0

	# 10. Update score berjalan
	update_score()
```

## A16. DIFFICULTY SCALING

```
Consumption_multiplier(day) = 1 + 0.02 × day
Event_severity_multiplier(day) = 1 + 0.015 × day
Package_reward_multiplier(day) = 1 + 0.01 × day
```
Dipakai sebagai pengali tambahan di formula A14 (konsumsi), A9 (efek event), A8 (reward package).

### Skor Akhir
```
Score = (total_days_survived × 100) + (total_credits_earned × 1) + (total_packages_delivered × 50)
```

---

# BAGIAN B — STRUKTUR FOLDER

## Target (sesuai GDD S17)

```
res://
  data/
	cards/
	  nodes/*.tres         # NodeCardData
	  items_raw/*.tres     # ItemCardData (RAW)
	  items_processed/*.tres
	  items_food/*.tres
	  tools/*.tres         # ToolCardData
	  buildings/*.tres     # BuildingCardData
	  units/*.tres         # UnitCardData
	recipes/*.tres         # CraftRecipe
	events/*.tres          # EventCardData
	packages/*.tres        # PackageCardData template per sektor
	sectors/*.tres         # SectorData (jarak, rep_required, reward_multiplier)
	packs/*.tres           # PackDefinition (harga_dasar, drop_table)
  scripts/
	core/
	  card_base.gd
	  card_types/ (node_card.gd, unit_card.gd, building_card.gd, ...)
	systems/
	  day_cycle_manager.gd   # implementasi A15
	  recipe_resolver.gd     # implementasi A13
	  economy_manager.gd     # pack, sell, credits — A10 A12
	  event_manager.gd       # A9
	  package_manager.gd     # A8
	  difficulty_manager.gd  # A16
	ui/
	  board_drag_drop.gd
	  hud_stats.gd
```

Prinsip: **semua angka/isi/resep ada di file `.tres`**, script cuma baca & eksekusi rule generik. Nambah kartu/resep/event baru = bikin file `.tres` baru, tidak perlu ubah script.

## Struktur saat ini (sudah ada — masih prototype, akan di-refactor)

```
game/
├── main.tscn              (scene utama — diset di project.godot)
├── scenes/card.tscn + card.gd    (kartu prototype: click/drag/stack — Phase 0)
├── scenes/stack.tscn + stack.gd  (pile/dropzone prototype — Phase 0)
└── scripts/main.gd        (spawn kartu test)
```

Catatan: prototype Phase 0 akan di-refactor menjadi sistem CardData (Resource) + board 2 zona sesuai bagian A.

## Prinsip Pengembangan — Placeholder Visual

- **Belum ada sprite/gambar apa pun.** Semua kartu memakai placeholder: panel berwarna + teks `display_name` (kayak prototype Phase 0: Panel + ColorRect + Label).
- Field `icon: Texture2D` di `CardData` dibiarkan kosong dulu (opsional), visual utama = warna + nama.
- Sprite/icon/gambar dikerjakan **terakhir** (bagian polish), saat semua sistem gameplay sudah jalan.
- Tiap card type boleh punya warna placeholder khas biar mudah dibedakan saat playtest (mis. Resource = abu, Food = oranye, Tool = biru, Building = ungu, Unit = hijau, dst).

---

# BAGIAN C — ROADMAP IMPLEMENTASI (urutan build satu-per-satu)

- [x] **Phase 0 — Fondasi kartu prototype:** click, drag, stack, pile (selesai, masih dipakai dasar interaksi)
- [x] **Phase 1 — Fondasi Data:** `CardData` + subclass (Node/Unit/Item/Tool/Building/Package/Event) sebagai Resource scripts, `CraftRecipe`, enum global (CardCategory, UnitRole, dll), autoload `GameState` + DB loader, dan file `.tres` data awal (nodes, items, tools, buildings, units, recipes, sectors, packs)
- [x] **Phase 2 — Board & Drag-Drop:** board 1 scene 2 zona (`SHIP_INTERIOR`, `OPEN_SPACE`), validasi drop per kategori, item stacking, visual card dari CardData
- [x] **Phase 3 — Combine Engine:** `recipe_resolver.gd`, manual combine instan (A13) — termasuk resep promosi role unit (A4a)
- [x] **Phase 4 — Node & Gather:** real-time gather interval, durability node, output spawn (A3)
- [x] **Phase 5 — Unit & State Machine:** role, IDLE/WORKING/TRAVELING/DEAD, efficiency map, kebutuhan food/O2/power (A4)
- [x] **Phase 6 — Building & Power:** build cost, power_draw, produksi harian, auto-shutdown prioritas (A7, A14)
- [x] **Phase 7 — Day Cycle:** `day_cycle_manager.gd` — End Day tick 10 langkah, konsumsi, kematian, difficulty scaling, game over (A14, A15, A16)
- [x] **Phase 8 — Ekonomi & Pack:** credits, sell di Trade Post, card pack + drop table, harga progresif (A10, A12)
- [x] **Phase 9 — Package & Sektor:** assembly requirement, keberangkatan TRAVELING, reward formula, unlock sektor (A8)
- [x] **Phase 10 — Event System:** event card, weighted spawn, PLAYER_CHOICE, durasi efek (A9)
- [x] **Phase 11 — O2 Tether:** O2 Umbilical Station, Portable O2 Tank, status O2_CUT (A1.2)
- [x] **Phase 12 — UI Lengkap:** HUD stat kapal, tombol End Day, area buka pack, layar game over + skor (A11, A16)
- [x] **Phase 13 — Balancing & Polish:** tuning angka, keputusan open question di A18

---

# BAGIAN D — PROGRESS LOG

- **Phase 0 selesai** — kartu prototype bisa click (signal `clicked`), drag, dan stack ke pile; klik pile untuk pop kartu. Main scene = `main.tscn`, verifikasi headless bersih (Godot 4.7.1 Steam di `D:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`). Satu bug sempat muncul (`:=` infer Variant di stack.gd) — sudah diperbaiki.
- **Phase 1 selesai** — Fondasi data lengkap: enum global (`Enums`), `CardData` + 8 subclass, `CraftRecipe`, `SectorData`, `PackDefinition`, autoload `GameState`/`CardDB`/`RecipeDB`, 83 file `.tres` (59 kartu, 14 resep, 5 sektor, 5 pack). Validasi `tests/data_check.gd` lolos: `kartu: 59 | resep: 14 | sektor: 5 | pack: 5` → `DATA CHECK: OK`; run normal headless bersih.
- Keputusan teknis Phase 1: sub-resource bertipe script class (`ItemRequirement`, `ProductionRule`, `EventChoice`) **diganti Dictionary** di `.tres` karena runtime headless tidak mendaftarkan script class ke ClassDB (`Cannot get class 'ItemRequirement'`) — Dictionary selalu bisa di-parse di mode apa pun. File script pendukung (item_requirement.gd, production_rule.gd, event_choice.gd) dihapus; akses data via key dict (`req["item_id"]`, `prod["input_item_id"]`, dst).
- Catatan Phase 1: file `.tres` harus tanpa UTF-8 BOM (PowerShell `Set-Content -Encoding UTF8` menambahkan BOM → `Parse Error: Expected '['`); `role` unit diperbaiki dari off-by-one (astronaut=0, engineer=1, scientist=2, pilot=3, robot_drone=4), validasi role sekarang ada di data_check.gd.
- **Phase 2 selesai** — Board 1 scene 2 zona: `scripts/ui/board.gd` (klas `Board`, zona `SHIP_INTERIOR` kiri 45% / `OPEN_SPACE` kanan 55% + garis airlock, `validate_drop()` per kategori, spawn test dari CardDB, label debug data). `scenes/card.gd|card.tscn` di-refactor: render dari `CardData` (panel + warna placeholder per kategori + nama + label ×N + label kategori), item stacking otomatis (drop item sejenis → merge sampai `stack_max`, sisa pecah jadi kartu baru), drop invalid → revert + flash merah. Aturan drop: BUILDING & PACKAGE hanya Zona Kapal, NODE hanya Zona Angkasa, UNIT/ITEM/TOOL bebas. NODE & EVENT tidak bisa di-drag. `scripts/main.gd` dihapus (diganti board.gd). Verifikasi headless bersih.
- **Phase 3 selesai** — Combine Engine (A13): `scripts/systems/recipe_resolver.gd` (klas `RecipeResolver`, static): `find_recipe()` cek 2 arah dengan kuantitas stack (input ≤2 jenis; resep 1-input = drag material ke atas Unit, mis. Scrap ×3 ke Engineer → Mining Drill), `check_blocked()` (building prasyarat harus ada di board, unit role harus ada), `execute()` (konsumsi input dari stack, spawn output di titik drop). `board.gd`: `_on_card_dropped` (cari kartu target di titik drop → resolve → toast hijau "+ Output" / merah "Butuh X"), `has_building()`, `has_unit_role()`, `spawn_card_at()`. Resep produksi building (`duration_days > 0`) sengaja di-skip manual combine (diproses Phase 6/7). Test otomatis `tests/combine_check.tscn|gd`: 12 kasus pencocokan + 3 alur eksekusi/blokir → `COMBINE CHECK: OK`. Test board Phase 3 berisi material semua resep manual.
- **Phase 4 selesai** — Node & Gather (A3): drag Unit ke Node → `assign_to_node()` (Unit menempel di sisi kanan Node, label "WORKING"), timer gather real-time di `board._tick_gather()` — `effective_interval = gather_interval_sec / efficiency` (efficiency dari `role_efficiency_map` node id, default 1.0). Tiap harvest: `_spawn_nearby()` output di slot kosong terdekat (ring 8 posisi, fallback acak), secondary output (Alien Ruins 50/50) via `secondary_chance`. Node limited (`is_limited`): durability runtime di card (bukan resource bersama — `node_durability_left`, tampil "DUR X"), habis → node hilang, unit balik IDLE. Tool requirement (Gas Cloud butuh Cutting Laser): `has_tool()` cek tool card di board (v1 — sistem equip formal di Phase 5). Drop unit ke tempat kosong → unassign. Test `tests/gather_check.tscn|gd`: 6 alur → `GATHER CHECK: OK`; semua validasi lain tetap OK.
- **FIX TEST PALSU (penting):** `combine_check.gd` & `gather_check.gd` memanggil fungsi alur (yang berisi `await`) TANPA `await` di `_ready` → `_ready` langsung lanjut ke `print OK` + `quit(0)` SEBELUM alur selesai → "OK" selama ini PALSU. Diperbaiki: `await _run_combine_flow_tests()` / `await _run_gather_tests()`; flow combine kini mencari kartu via `board.get_children()` (bukan group — kartu `_make_card` di (0,0) mengganggu `_card_at`); asersi scrap flow A dikoreksi 8-2=6. Setelah fix, gather menemukan bug nyata: harvest gagal karena delta frame headless terlalu kecil untuk `interval - 0.01` → timer sekarang di-set `interval + 0.1`. **Semua test sekarang benar-benar menjalankan alurnya.**
- **Phase 5-13 selesai (satu paket):** 
  - **A4 unit state machine:** `unit_state` IDLE/WORKING/TRAVELING/DEAD di `card.gd`, status di label kartu; kematian → kartu hilang.
  - **A5/A6 tool equip:** drag Tool → Unit = equip (kartu tool dikonsumsi, tampil "EQ: ..."). Tool requirement node (Cutting Laser) sekarang cek equip unit (bukan board). Consumable (Repair Kit → Hull +20, dipakai drag ke Unit). Mining Drill → gather Asteroid Field ×2 (efficiency × effect_value). Portable O2 Tank → `tank_days_left`.
  - **A7 building:** drop kartu building = bayar `build_cost` dari item di board (konsumsi otomatis, toast "Butuh: ..." jika kurang) → `is_built` (tidak bisa di-drag lagi). Drag Unit → building = WORKING (slot `max_unit_slots`). Produksi harian: End Day, butuh unit + power + bahan.
  - **A14/A15 Day Cycle:** autoload `DayCycle.end_day()` 11 langkah: produksi → konsumsi food stock (4/unit × multiplier) → replenish O2 canister (25/unit) → stat → power (generated solar + cap 50, auto-shutdown bangunan non-life-support urut power_draw terbesar, nyala ulang jika cukup) → tether/O2_CUT → kematian (O2=0 25%/hari, food 3 hari 1 unit; Med Bay cegah 1/hari) → traveling → event → efek durasi berkurang → game over → skor.
  - **A16 scaling:** consumption ×(1+0.02×day), event severity ×(1+0.015×day), reward ×(1+0.01×day); skor = hari×100 + kredit + paket×50.
  - **A8/A9/A10/A12:** autoload `Packages` (assembly item→package "x/y"→READY, depart unit → TRAVELING, `travel_days = jarak sektor`, Pilot −1 hari, reward di End Day, sektor terkunci rep), `Events` (roll harian P=clamp(0.15+0.01d), pick berbobot `spawn_weight`, DAMAGE_HULL/O2, STEAL_RESOURCE, POWER_DEBUFF durasi, BUFF_LOOT meteorite, PLAYER_CHOICE via kartu event + popup HUD), `Economy` (jual di Trade Post `sell_value × rarity mult`, pack harga progresif +5% per pembelian, buka pack drop table berbobot).
  - **A1.2 tether:** drop unit ke Zona Angkasa butuh slot O2 Umbilical Station (2) atau Portable O2 Tank; label "TETHERED"; End Day: station mati listrik → "O2 CUT!" (25% mati/hari), tank berkurang/hari.
  - **A11 UI:** `scripts/ui/hud.gd` — stat bar (Hari/O2/Food/Hull/Power/Cr/Rep/Skor), tombol End Day, tombol beli 5 pack, popup pilihan event, layar Game Over + skor + tombol Main Lagi.
  - Test baru `tests/gameplay_check.tscn|gd`: 8 alur (repair kit, build cost, jual, produksi End Day, package, tether, event choice, game over) → `GAMEPLAY CHECK: OK`. Semua validasi: `DATA CHECK: OK`, `COMBINE CHECK: OK`, `GATHER CHECK: OK`, `GAMEPLAY CHECK: OK`, run headless 240 frame bersih.
- **Playtest fix (user):** kartu dikecilkan 25% (120×170 → 90×128, font & posisi elemen di-scale); offset assign unit & ring spawn kartu ikut disesuaikan. **Produksi building diubah dari End Day → real-time** (Stacklands-style): `board._tick_production()` — progress bar kini tampil di kartu unit saat WORKING di building produksi (interval = `interval_days` × 10 detik, pause jika bahan kurang / tanpa worker / mati listrik), bahan dikonsumsi + output spawn saat bar penuh. Step produksi dihapus dari `DayCycle.end_day`. Test gameplay alur D disesuaikan; semua validasi tetap OK.
- *(isi log di sini tiap ada perubahan)*
- **Pack gated (user):** buka pack tidak lagi cuma Credits → butuh basic resource dulu + random tetap (Stacklands-style). `PackDefinition.resource_cost: Array[Dictionary]`, `Economy.buy_pack()` cek `board.count_item` → toast "Butuh: ..." jika kurang → `spend_credits` → `consume_item` → `open_pack()` (weighted random tidak berubah, reward event `grant_pack` tetap gratis). Isi awal: Salvage = Scrap ×2, Tech = Scrap ×2 + Space Ore ×2, Recruit = Water ×2 + Scrap ×2, Alien = Alien Flora ×1, Mystery = gratis. Label tombol HUD via `Economy.pack_label()` ("10 cr + 2x Scrap Metal"). Validasi `data_check.gd` cek `resource_cost` ref & qty.
- **Resep diganti PDF Combining Recipe (user):** 37 → 19 resep. Dihapus 18 file: `alien_extract`, `circuit_board`, `cutting_laser`, `feast_meal`, `fuel_cell`, `metal_ingot`, `mining_drill`, `oxygen_canister`, `portable_o2_tank`, `promote_engineer|pilot|scientist`, `protein_paste`, `repair_kit`, `robot_drone`, `water_melt`, `welding_torch`, `build_helper_charger_station` (di PDF masih ragu-ragu). Tabel A13 diganti daftar PDF. Catatan: kartu-kartu lama (Circuit Board, Scrap, dsb) tetap ada sebagai data (dipakai pack drop & test board), hanya resepnya yang dihapus. Sistem promosi role A4a ikut nonaktif (resepnya dihapus).
- **Fix prioritas combine (akibat PDF):** resep sesama-item (Water+Water, Iron+Iron) tidak bisa ke-trigger via drag karena `_try_merge_stack()` di `card.gd` selalu merge duluan — sekarang cek `RecipeResolver.find_recipe()` dulu, kalau cocok diteruskan ke Combine Engine. `combine_check.gd` ditulis ulang ke resep PDF (find 12 kasus + flow A/B/C: oxygen tank, excavation tools, dirt chain). Semua validasi OK (data/combine/gather/gameplay + main 240 frame).
- **Bersih-bersih kartu (user, 86→74):** dihapus 12 kartu orphan tak bersistem: `building_cargo_bay`, `building_helper_charger_station`, `item_asteroid|ice_block|iron_deposit|space_debris` (calon breakable PDF, belum ada sistemnya — bikin lagi saat sistemnya ada), `item_protein_paste|ration_pack`, `tool_heat_source|processor`, `unit_pilot|robot_drone`. Drop pack di-remap ke item era-PDF: Salvage = water/iron/rock/food/mushroom/ice; Tech = iron/ore/rock/energy/component/excavation/star map; Mystery = campur PDF + tool/unit fungsional; Alien & Recruit tetap. Test board: 3 spawn kartu terhapus dibuang. Yang SENGAJA dipertahankan walau non-PDF (load-bearing): scrap/ore/gas/ice/circuit/fuel/ingot/crystal/alien (node output, build cost, package, pack cost), cutting laser (syarat gas node), mining drill (efek di `_unit_efficiency`), repair kit (consumable + gameplay), portable tank, engineer/scientist (test + mystery), paket & event lama (konten valid). Follow-up: loop survival lama (smelter/refinery/oxygen-gen) masih jalan pasif tapi outputnya makin sedikit dipakai — diputuskan di balancing/GDD lanjutan.
- **Intro buka-pack (user):** game baru (non-headless) tidak lagi langsung tumpuk kartu debug — muncul overlay "HARI 0 — PERBEKALAN AWAL" (z 600, blokir input): panel Paket Perbekalan → tombol "Buka Pack" (punch tween) → 6 mini kartu starter reveal staggered pop → tombol "Ke Board" → starter kit spawn di Zona Kapal dengan pop + overlay fade. Starter: Astronaut ×1, Water ×2, Space Rock ×2, Iron ×2, Food ×1, Mushroom ×1; node dunia (asteroid/debris/ice/gas) sudah ter-spawn di belakang overlay. Headless/test tetap pakai `_spawn_test_cards()` instan; `Board.force_intro` + `tests/intro_check.tscn|gd` memverifikasi alur intro → `INTRO CHECK: OK`.
- **Paket O2 A+B+C (user, portable jangan terlalu susah/mudah):** temuan audit — resep portable ikut terhapus kemarin (sumber tinggal Mystery Pack) + Mystery `base_cost = 0` masih ada tombol belinya (farm gratis) + O2 Station butuh Circuit ×2 yang sudah tak obtainable (station tak bisa dibangun, tether mati). Perbaikan: (A) resep baru `recipe_portable_o2_tank` = Water ×1 + Component ×2 (4 iron + 1 water + 2 langkah combine, tanpa building — awalnya Iron ×2 + Component ×1 tapi itu subset-ambiguous dengan Excavation Tools dan engine ambil match pertama, jadi diganti yang disjoint; tematik: O2 dari water); (B) build cost O2 Station `circuit ×2 → component ×2` (ingot ×4 via smelter tetap) — station = investasi permanen 2 slot, portable = darurat 3 hari; (C) `PackDefinition.shop_visible` + Mystery `shop_visible = false` (reward-only sesuai GDD A12, tetap didapat via event `grant_pack`) — HUD hanya bikin tombol pack yang `shop_visible`. Test: kasus portable masuk combine_check; semua validasi OK (74 kartu | 20 resep).
- **Layout HUD + Buku Resep (user, dari screenshot):** End Day pindah kanan-bawah; tombol pack dijejer horizontal di kirinya (urutan abjad, nama node `PackBtn_<id>`); tombol "Resep" di kiri-bawah membuka panel Buku Resep (scroll, 20 resep `input → output + syarat`, toggle buka/tutup). Stat bar digeser ke (16,34) agar tidak tabrakan label zona. Sekalian fix bug label pack (semua tombol keliru tampil pack pertama karena refresh berbasis posisi — sekarang berbasis nama node). Verifikasi via smoke test sementara (20 baris, toggle, tombol lengkap, mystery tanpa tombol → OK, file dihapus lagi).
- **Alien Pack disederhanakan (user):** rantai alien sebenarnya konsisten (event Trade → pack gratis → flora/crystal → Science Lab → extract → Med Bay) — yang membingungkan hanya pack-nya dijual di toko seharga Flora ×1 padahal isinya Flora juga (sirkular). Jadi `pack_alien.shop_visible = false` (reward-only, dapat via `grant_pack`), biaya flora dihapus.
- **Sync GDD Finpro (user):** (a) restore `unit_pilot` (role 3, bonus travel −1 hari) + `unit_robot_drone` (role 4, tanpa Food/O2, butuh Power, efisien mining 1.5) — GDD S2.3; (b) Recruit Pack jadi mix Astronaut 70 / Engineer 12 / Scientist 10 / Pilot 8 + Mystery ketambahan Drone (kru via Recruit Pack, GDD S3.1); (c) `PackDefinition.rep_required`, Tech = 20 (sejajar unlock Asteroid Belt) — Rep membuka pack tier tinggi, GDD S4.2; `buy_pack` tolak + toast kalau Rep kurang, label tampil "Rep 20"; (d) starter kit +Scrap ×2 agar hari 0 langsung bisa buka Salvage Pack (GDD S3.3), test intro diupdate; (e) Main Menu baru (`scenes/menu.tscn` + `scripts/ui/menu.gd`, Mulai/Keluar, main scene project dialihkan ke menu, board tetap `main.tscn` agar test tidak berubah) — GDD S4.3, Continue/Options absen sesuai GDD (butuh save/load, out of scope); (f) SFX prosedural DICABUT lagi atas permintaan user ("nanti aja") — file + autoload + 8 hook dihapus, slotnya didokumentasikan di sini buat nanti. Semua validasi OK (76 kartu | 20 resep).
- **Intro pilih 1 dari 3 pack + rapikan kode UI (user):** intro tidak lagi 1 paket fix — `scripts/ui/intro.gd` (`IntroOverlay`, data-driven `INTRO_PACKS`): Survivor (food/water), Miner (iron/scrap, langsung bisa beli Salvage), Technician (energy/component). Tiap pack tampil isi + tombol Choose (satu pilihan, terkunci), lalu reveal minis + Start; board spawn kit pilihan via signal `finished(kit)` (slot grid otomatis). Nambah pack ke-4 = tambah 1 dictionary, tanpa logika baru. `scripts/ui/ui_factory.gd` (panel/label/button satu baris) dipakai intro + menu + buku resep. Hasil: board.gd 721→613 baris; total script 2040→2051 (file baru intro+factory), duplikasi pembuatan UI hilang. Catatan teknis: file `class_name` baru wajib scan editor sekali (`.godot/global_script_class_cache.cfg`, gitignored) agar test headless kenal — perintahnya `--headless --editor --quit`. `intro_check` ditulis ulang ke alur pilih (3 tombol, kunci anti-ganti, assert isi kit pack 0). Semua validasi OK.
- **Nama package English (user):** 5 package quest (`Scrap Run`, `Ore Haul`, `Fuel Resupply`, `Deep Void Relay`, `Alien Crystal Delivery`, +deskripsi) dan 3 pack intro (`Survivor/Miner/Technician Pack`, tombol `Choose`/`Start`, test diupdate). Judul/sub intro ditulis user sendiri.
- **Intro tetap gelap + centering presisi (user):** dim 0.78 dipertahankan; judul/sub jadi full-width (center beneran di semua resolusi); baris pack & minis dihitung dari lebar konten aktual (panel+gap), bukan asumsi step — sebelumnya meleset ~10px ke kiri. Perbaikan lanjutan: overlay pakai ukuran eksplisit (`size = view`, bukan anchor) agar fill gelap selalu tampil; layout kolom jadi vertikal-center penuh (judul-sub-pack-mini-tombol satu kolom simetris).
- **Frame kartu per zona (user, asset baru):** `card.tscn` + layer `FrameTexture` (belakang, fallback placeholder kalau PNG belum ada); `card.gd:refresh_zone_frame()` pilih biru/coklat dari zona posisi kartu — dipanggil saat spawn, drop, dan unit pulang travel. File yang perlu disimpan user: `assets/cards/card_frame_ship.png` (biru) + `assets/cards/card_frame_space.png` (coklat); buka project di editor sekali agar ke-import. Semua validasi OK tanpa PNG (jalur fallback).
- **Tombol pack: nama saja + info hover (user):** label panjang (`Tech Pack (30 cr + ...)`) bikin tombol overlap — teks tombol kini cuma nama pack. Tooltip bawaan ternyata tidak muncul, jadi diganti label info khusus di atas barisan tombol (`mouse_entered/exited` → tampil rincian biaya, ikut update saat harga naik). Tooltip_text tetap dipasang sebagai cadangan.
- **Background main menu (user, asset baru):** `menu.gd` tampilkan `assets/ui/main_menu_bg.png` (cover full-screen, fallback warna gelap kalau belum ada; judul teks disembunyikan kalau bg ada karena logo baked-in). File perlu disimpan user + buka editor sekali agar ke-import. Tombol ikut mockup: teks rata-kiri tanpa kotak (`flat`), font 36, hover biru muda, posisi kiri-bawah logo; font italic serif opsional via `assets/ui/menu_font.ttf` (fallback font default kalau belum ada).
- **Panel kartu transparan (user, "full tanpa putih"):** root Panel pakai `StyleBoxEmpty` agar background putih tidak mengintip di tepi frame; gaya putih lama pindah ke kode sebagai fallback saat PNG belum ada (`_fallback_panel_style`). Lanjutan (user, "stretch dilebarin"): `FrameTexture` di-bleed 6px keluar tiap sisi (rect -6,-6,96,134) agar art nutup penuh; sisa margin (kalau ada) tampil sebagai board gelap, bukan putih. Catatan: kalau putih masih terlihat setelah PNG dipasang, berarti margin putih baked-in di file PNG-nya — solusinya crop file (bisa via System.Drawing, tidak perlu install apa pun).
- **Insiden file korup (pelajaran):** `intro.gd` sempat parse-error + hang test setelah edit manual — penyebabnya satu karakter non-ASCII yang kesimpan dengan encoding lain (terbaca `�`). Solusi: tulis ulang file bersih + hindari karakter non-ASCII di kode. Aturan baru: jangan pakai karakter non-ASCII di file `.gd`/`.tres` (teks UI Indonesia tetap boleh di string biasa, tapi aman pakai ASCII saja).
- **O2 bocor saat EVA (user):** tiap End Day, unit bernapas di Zona Angkasa menambah konsumsi O2 (`EVA_O2_EXTRA = 3.0`, ikut difficulty multiplier) + toast `EVA: -X O2`. Drone tidak kena. Verifikasi smoke sementara: 1 unit di luar dari 3 kru → O2 100 → 81.64 pas hitungan ((5x3+3x1)x1.02).
- **EVA jadi real-time (user):** surcharge End Day dicabut (anti double-charge); `board._tick_eva_oxygen()` kuras O2/detik/unit di luar kapal + clamp 0 + refresh HUD; unit TRAVELING dikecualikan. Lanjutan (user): tanpa Portable O2 Tank bocor cepat (`2.0`, angka user), dengan tank terpasang melambat (`0.15`) — cek `has_equipped_tool`. Verifikasi: tanpa tank 10 dtk = -20.0, dengan tank = -1.5, OK.
- **Buku resep nama-dulu (user):** `_recipe_line()` kini `Nama Hasil [xN]` baris 1 + `Bahan: ... | syarat` baris 2 (sebelumnya `bahan = hasil`).
- **Waktu linear, End Day dihapus (user):** `DayCycle` jalan per-frame (`DAY_LENGTH = 70.0`, angka user) — O2/food/power terkuras per-detik dengan angka/hari lama dibagi 70; travel/event/kematian/efek diskalakan fraksional (`1-(1-p)^frac`); hari auto-increment + HUD `Hari N` + progress bar hari (track 220px di bawah stat, fill biru update per-frame via `DayCycle.day_progress()`); stok canister/food auto-top-up hanya saat defisit muat penuh (anti waste spiral).
- **Preview combine + split stack (user):** drag kartu ke atas kartu lain kini menampilkan label preview (`board.update_combine_preview`, hijau `+ Hasil` / merah alasan syarat, sembunyi saat drop/posisi kosong); klik kanan stack item (isi >1) membelah dua via `card._split_stack()` (total tetap, isi 1 diabaikan). Gabung kartu sama memang sudah ada dari awal (`_try_merge_stack`, combine tetap prioritas atas merge). Verifikasi smoke sementara → OK, file dihapus.
- **Resep bisa-dibuat dipin ke atas (user):** `_refresh_recipe_highlights()` kini memindahkan baris hijau ke paling atas secara stabil (urut relatif dipertahankan, reorder hanya saat komposisi berubah agar scroll tidak lompat). Sekalian betulkan bug: buku resep ternyata kebangun 2x (baris ganda) sejak refactor tscn — sekarang sekali. Verifikasi smoke sementara (36 baris pas, hijau semua di atas) → OK, file dihapus.
- **Bug O2 nol + shake monster + telepon/market/SOS (user):** (1) O2 <0.5 di-snap ke 0.0 agar HUD yang membulatkan jujur dan counter `days_without_oxygen`/roll kematian tak ke-reset regen mikro. (2) serangan monster kini `add_shake(10)` — board bergetar dan reda ±0.3 dtk. (3) `item_space_telephone` (TOOL, resep: Component x2 + Energy Cell) — selama ada di board, tombol Market (kiri-bawah) terbuka: panel jual resource per-unit (Jual 1/Semua, prorata) + berangkatkan paket via unit bebas. (4) paket darurat `pkg_emergency_sos` (Food x3 + Water x2, 120 dtk, label `SOS 87s 2/5`): spawn otomatis tiap 90 dtk (pertama 45 dtk) selama telepon ada; lengkap → reward instan +cr/+rep; gagal → hangus; tak bisa di-depart biasa. Verifikasi smoke sementara → OK, file dihapus.
- **Resep beginner-friendly + starter pack berkarakter (user):** (1) Energy Cell kini bisa di-craft (`Iron x2 + Scrap`, sebelumnya cuma drop Tech/Mystery yang ke-gate credits+Rep — dead-end untuk Technician/telephone/helper). (2) Portable O2 Tank disederhanakan jadi `Water + Component` (2 iron + 1 water, dari 4 iron). (3) Helper Station `Component x3 → x2`. (4) Starter pack dirombak 6 slot + selalu Water x2 (syarat oksigen): Survivor = food/water sustain (minus: tanpa iron, tech lambat); Miner = iron3/rock2/scrap2 (minus: food tipis); Technician = energy+component+iron2 (minus: food tipis, bahan habis pakai). Semua validasi OK (84 kartu | 38 resep).
- **O2 fuse 5 detik + search/sort resep (user):** (1) akar bug O2 0 tak mati: aturan lama butuh 5 HARI tanpa oksigen. Kini sekring 5 DETIK (`_o2_fuse`, toast merah "O2 HABIS!" saat mulai) — terasa langsung tapi aman dari flicker; legacy `end_day` sinkron via `days*70`. (2) buku resep dapat kolom search (nama/bahan) + dropdown sortir "Bisa dibuat/A-Z/Jenis", reorder tetap anti-lompat via signature. Verifikasi smoke sementara → OK, file dihapus.
- **Pangkas resep mati (user):** dihapus `Food→Power` (+ kartu `item_power`, tak ada yang memakai Power), `Space Navigator` (+ kartu + Star Map yang yatim; deskripsinya sendiri bilang belum terhubung) beserta spawn test-nya, dan `Heat Source` (+ kartu; tak obtainable). `Mencairkan Es` diselamatkan jadi resep Structure (Ice Chunk → Furnace/Little Furnace → Water) agar Ice Field tetap berguna; Star Map di Tech Pack diganti Component. Yang dipertahankan walau niche: Mining Drill (efek 2x asteroid di kode), Promote trio + Drone (progresi unit), Feast/Protein/Alien (rantai food top-tier), Circuit/Metal/Fuel (biaya building). Semua validasi OK (80 kartu | 36 resep).
- **Pangkas kartu yatim (user):** `Scanner` (0 referensi di seluruh project), `Processor` (tak obtainable → rantai Protein/Feast keblokir; resep Protein Paste dialihkan ke Extract + Mushroom sehingga rantai alien justru kebuka), `Cargo Bay` (pasif stack bonus tak pernah diimplementasikan di kode + tak obtainable), `Ration Pack` (tak ada di pack/board/kode mana pun; peran food ditutup Food/Mushroom). Meteorite + Artifact dipertahankan (sumber duit via jual). Semua validasi OK (76 kartu | 36 resep).
- **Water bisa di-stack + slot tool astronot (user):** (1) resep Oxygen Tank diganti `Water + Ice Chunk` (Water+Water selalu kecolong jadi craft, tidak pernah bisa numpuk) — starter pack disesuaikan: Survivor rock→ice2, Miner scrap2→ice1, Technician tetap (es via Ice Field); test combine/highlight diperbarui. (2) tiap unit max 2 slot tool (`Card.MAX_TOOL_SLOTS`, consumable tak kena cap); klik kanan unit membuka popup 2 slot berisi tombol Lepas (kartu tool kembali ke board) + Tutup. Verifikasi smoke sementara → OK, file dihapus.
- **Portable O2 dihapus + pangkas torch (user):** (1) `tool_portable_o2_tank` + resepnya dihapus; efek +25 O2 pindah ke `item_oxygen_tank` yang diubah jadi TOOL consumable (resep Water+Ice tetap); cabang EVA-with-tank yang mati dirapikan (drain flat 2.0). (2) `Welding Torch` (+ resep) dihapus — tak ada efek sendiri, cuma perantara; Repair Kit disederhanakan jadi Scrap ×2 + Iron. Daftar tool akhir (6): Excavation (bahan upgrade Excavator), Mining Drill (gather asteroid 2x), Cutting Laser (syarat Gas Cloud), Repair Kit (+20 Hull), Space Telephone (unlock Market), Oxygen Tank (+25 O2). Mystery pack: slot portable → Oxygen Tank 45. Test gameplay/combine diperbarui. Semua validasi OK (74 kartu | 34 resep).
- **Pack masuk Market + Trade Post dihapus (user):** tombol pack bawah dihapus total (kode + node tscn + hover); beli pack pindah ke section BELI PACK di panel Market; `buy_pack` menolak bila tak ada telepon. Trade Post dihapus (kartu + drag-sell + spawn test); jual kini hanya via Market (per-unit). Test gameplay C ditulis ulang (sell 1 water +3cr). Semua validasi OK (71 kartu | 34 resep).
- **Quest final ganti misi sektor (user):** `pkg_quest_beacon` (Component×3+Iron×4+Water×2, →debris) lalu `pkg_quest_warp` (Fuel×2+Circuit×2+Extract×1, →asteroid) — spawn linear via telepon (Q1 otomatis, Q2 saat Q1 tiba); Q2 tiba → MENANG! Progres `Quest n/2` di stat bar; paket biasa tetap untuk duit/rep. `delivered_sectors` dihapus total (state/save/stats). Verifikasi smoke sementara → OK, file dihapus.
- **Save/load dibuang + slider terlihat (user):** SaveManager + autoload + tombol menu/Load + logika pending dihapus total (volume pindah ke GameState, settings hanya Suara/Main Menu/Exit); slider art dikembalikan ke theme default agar kelihatan. Semua validasi OK.
- **Font menu revert + log kejadian (user):** (1) main menu kembali font default Godot (`GameState.default_font` disimpan sebelum override; menu pakai itu). (2) log 6 baris terakhir kanan-bawah (`EventLog`, font 13 rata kanan + outline) — semua toast board otomatis masuk via `_show_toast`. Bug ditemukan saat itu: `add_log` infinite-loop (`queue_free` deferred di `while count`) saat toast ke-7 → hang combine; diperbaiki dengan `remove_child` dulu.
- **Misi final: layani 5 sektor → menang (user):** kontrak paket spawn otomatis tiap 75 dtk (pertama 20 dtk, max 2 aktif, prioritas sektor belum terlayani); tiap tiba dicatat (`delivered_sectors`, toast progres); 5/5 → layar MENANG! hijau + game berhenti. Progres `Sektor n/5` di stat bar. Ikut tersimpan di save (termasuk sector paket-traveling). Verifikasi smoke sementara → OK, file dihapus. Revisi: misi sektor diganti quest linear (lihat entri quest); kontrak biasa kini HANYA jalan bila telephone ada (`has_market` gate, sesuai permintaan).
- **Hapus Hull Breach + Engine Malfunction (user):** tak ada kaitan kode/test; tabel plan dibersihkan. Sisa 6 event acak + monster hari-4. Semua validasi OK (69 kartu | 34 resep).
- **Hapus Solar Flare (user):** tak ada kaitan kode/test; tabel dibersihkan. Sisa 5 event acak + monster hari-4. Semua validasi OK (70 kartu | 34 resep).
- **SFX prosedural + 1 tool per unit + intro fade (user):** (1) autoload `Sfx` (`scripts/systems/sfx.gd`, tanpa file audio): stack = thock rendah, combine = nada naik 2 tingkat, unstack = nada turun; pool 6 player, ikut volume Master. (2) slot tool dihapus: tiap unit max 1 tool, tak ada popup; klik kanan unit langsung melepas tool (kartu kembali ke board). (3) intro pilih-pack diganti scene teks-fade (4 baris berurutan + tombol Mulai) lalu spawn anim starter kit tunggal (Survivor); test intro ditulis ulang. (4) font menu → `game_font.ttf` (asumsi itu font bagusnya; ganti file-nya bila bukan). Semua validasi OK.
- **Art event popup (user):** `assets/cards/art_<event_id>.png` tampil 408×220 di popup OK maupun pilihan Trade/Flee (layout dinamis, panel 440×440); kartu event alien di board ikut dapat art otomatis via konvensi yang sama.
- **Shader vignette+grain dipakai (user):** `UIFactory.vignette()` dipakai board (z 400) + menu (z 100); intensitas dinaikkan (strength 0.65, grain 0.08) karena versi halus tidak terlihat.
- **Art panel resep & setting (user):** `panel_recipe.png` / `panel_settings.png` di `assets/ui/` (fallback stylebox lama); judul tengah + tombol X (ganti Tutup); setting: tombol Save/Load/Main Menu/Exit 330×44 sesuai mockup; resep: search + sort + bingkai emas area list. Perbaikan: file mockup ternyata berisi teks/UI baked-in → UI dobel; art panel DIMATIKAN via `PANEL_ART_ENABLED=false` sampai tersedia versi bersih (background + border saja). Revisi (user mau pakai art): art DINYALAKAN lagi; semua tombol jadi transparan tanpa teks tepat di atas slot baked (posisi diukur per-pixel dari file); judul/label yang baked dihapus dari kode; slider transparan; sort jadi tombol kecil ganti mode (Bisa/A-Z/Jenis); summary jadi baris pertama list; % volume dibuang (baked statis). Lanjutan: settings art baru 675×438 → panel 440×286 (aspek pas, tanpa distorsi), tombol di slot baked baru.
- **Art tombol HUD (user):** `btn_pause/play/recipe/setting.png` + `bar_day.png` di `assets/ui/` (opsional, fallback tombol teks). Pause↔Play ganti ikon saat pause; Day pakai art sebagai background track (fill+label tetap di atas).
- **Art stat bar (user):** `bar_stats.png` 5 segmen (O2|Food|Hull|Cr|Power) — hanya angka yang ditulis (label baked di gambar, proporsi gambar dijaga); Rep/Skor/Sektor jadi teks kecil di bawahnya; Hull bar digeser ke y84. Tanpa file → label teks lama. Lanjutan: angka rata kanan per segmen + pil gelap di belakang (terbaca walau gambar diganti); bar hari disamakan tinggi 48 (288×48, y8, fill ikut lebar track). Final: divider diukur per-pixel dari file (6/159/344/533/701/932 dari 940px, decoder awal cacat karena filter Paeth tak ditangani) — angka duduk tepat sebelum tiap divider, pil dibuang. Tombol persegi (Pause/Resep/Setting) 64×64. Pause pindah tengah-bawah. Animasi pencet (scale punch + back-ease) di Pause/Resep/Setting via `_juice_button`.
- **Load di main menu + Recipe sejajar Setting (user):** (1) tombol Load di menu (muncul hanya bila ada save) → `SaveManager.pending_load` → board baru lewati intro/spawn lalu `load_game()` (gagal load = mulai normal). (2) tombol Resep pindah ke kolom kiri-bawah (8–72, y −140–−76), sejajar di atas tombol Setting 64×64. Verifikasi smoke sementara → OK, file dihapus.
- **Tombol 57×57 + Pause atas-tengah (user):** Pause pindah tengah-atas (57×57); Resep & Setting ikut 57×57 (kolom kiri-bawah: Resep y −133–−76, Setting y −69–−12).
- **Setting + save/load + hapus label zona (user):** (1) tulisan ZONA KAPAL/ANGKASA dihapus (fungsi helper ikut dibuang). (2) tombol Setting 64×64 kiri-bawah (sejajar Resep); tombol Market geser ke kanannya (x80–220) agar tidak tumpuk. Panel: slider suara 0-100% (Master bus, tersimpan di `user://settings.cfg`, diterapkan saat boot), Main Menu, Keluar, Simpan, Muat. (3) `SaveManager` autoload: satu slot `user://savegame.cfg` menyimpan stat kapal, kartu (pos/stack/built/assign/equip/durability/assembly/meta), traveling (dengan snapshot paket), monster, cooldown SOS, dan waktu DayCycle; load membangun ulang + relink. Verifikasi smoke sementara → OK, file dihapus.
- **Art per kartu (user):** slot gambar di `card.tscn` (`ArtTexture`, aspect-centered) + konvensi `assets/cards/art_<card_id>.png` (fallback kotak warna kalau belum ada). Kartu astronot → `art_unit_astronaut.png`.
- **Art bersama per jenis (user, 56 file → 8):** fallback `card_art()` kini 3 tingkat: spesifik per kartu → bersama per jenis → placeholder. File jenis: `art_unit/node/building/tool/material(mentah+olahan+loot)/food/package/event.png`. File spesifik lama tetap menang (astronot + 4 event aman).
- **Inspect overlay (user):** klik kartu ber-art → overlay gelap (`InspectOverlay`, z 700) berisi art besar (±60% lebar × 72% tinggi layar) + nama + hint; klik untuk tutup. Kartu tanpa art tidak bereaksi. Verifikasi smoke sementara (termasuk art asli user terbaca) → OK, file dihapus.
- **Layout kartu ber-art full-bleed (user, ikut mockup):** art besar (aspect-covered) berhenti di y99 agar tidak menabrak nama (y100-126), label kategori disembunyikan, status naik ke slot kategori. Kartu tanpa art tidak berubah. Verifikasi smoke → OK.
- **Font global disamakan main menu (user):** `ThemeDB.fallback_font = menu_font.ttf` di `GameState._ready()` (autoload, selalu jalan) — semua Label/Button mewarisi, ukuran per-elemen tidak berubah. Lanjutan: path disatukan ke `assets/ui/game_font.ttf` (game_state + menu) — tinggal drop file TTF apa pun (mis. Iosevka Charon) dengan nama itu. Main menu belakangan dikembalikan ke font default, lalu diarahkan ke Sriracha via `assets/ui/menu_sriracha.ttf` (drop file-nya, fallback default bila absen).
- **Event random jadi popup OK (user):** `spawn_event` kini membuka popup (nama + deskripsi + ringkasan efek via `Events.event_summary`) dengan tombol OK; efek baru diterapkan saat OK ditekan; popup yang datang bersamaan antre. Test langsung `apply_event` tidak berubah. Verifikasi smoke → OK.
- **O2 regen + food game over + scene game over + monster (user):** (1) life support `O2_REGEN_PER_SEC = 0.15` — O2 nambah selama ada kru bernapas di dalam kapal (1-2 kru = net nambah, 3+ = tetap tekor; EVA 2.0/dtk dominan); legacy `end_day` ikut +10.5/hari. (2) food 0 selama 5 hari → game over "Kru mati kelaparan" (O2 sudah ada); layar game over kini scene dedicated `scenes/game_over.tscn` (`GameOverScreen`), panel lama di `hud.tscn` dihapus. (3) `event_space_monster` (weight 0, tak masuk roll acak): spawn sekali hari ke-4 di kanan, maju 140px/4 dtk via tween, sampai tepi kapal → mukul Hull 8/4 dtk; defense bar HULL muncul di kiri atas (hijau/kuning/merah). Cara lawan untuk sekarang: Repair Kit menambal Hull — senjata/pengusir monster follow-up. Verifikasi smoke sementara → OK (regen 70.5, foodover, goscreen, monster hull 92.0), file dihapus.
- **Background board (user, asset baru):** `board.gd` tampilkan `assets/ui/board_bg.png` full-board di belakang (stretch scale agar split pas; fallback warna datar kalau belum ada). Label zona dikasih outline biar kebaca di atas art. Lanjutan (user): split zona 45/55 → 40/60 kapal/angkasa (side effect: `pkg_scrap_run` test meniban ice field yang bergeser → pindah ke (940,800)); bar hari pindah kanan-atas diperbesar (304x28) dengan teks `Hari N` di dalamnya (keluar dari bar stat); tombol Resep jadi persegi 64x64 di tepi kiri tengah layar (kolom kartu mulai x=80, tidak overlap).
- **HUD pindah ke scene (user, "geser tombol"):** `scenes/hud.tscn` baru — Stats/DayBar/Pause/PackInfo/RecipeButton/popup/game-over jadi node scene ber-anchor (tombol bisa digeser di editor); pack buttons + isi buku resep tetap dinamis via kode ke container `PackButtons`. `board._spawn_hud()` instantiate tscn. Builder panel kode yang mati dihapus.
- **Layout board (user, dari screenshot):** garis divider disembunyikan; starter kit geser kanan (x 80→150, gap 120→130); node dunia disebar penuh (asteroid (180,140), gas (700,100), debris (650,420), ice (150,620) relatif zona — menuh dari x≈790 sampai 1430). Layout test (`_spawn_test_cards`) tidak diubah. `end_day()` dipertahankan sebagai legacy 1-hari-penuh untuk test. Tombol End Day → tombol Pause (`tree.paused`, HUD `PROCESS_MODE_ALWAYS`, restart unpause+reset). `days_without_*` jadi float; `resolve_travel`/`maybe_spawn_event` default `day_frac=1.0` (kompatibel). Semua test board set `DayCycle.enabled=false`. Verifikasi: fraksi 1.0 hari → O2 100→85 pas; tombol Pause/EndDay benar; pause bekukan tree. Smoke sementara dihapus.
- **SFX kartu ulang + musik menu/game (user):** SFX prosedural ditulis ulang total — tanpa nada sine, noise kertas lowpass 2 tingkat, format 16-bit (spawn = geser+snap, stack/drop = snap tegas, unstack = snap+geser, combine = 3 snap kocok, pickup/click = jentik). Musik: `assets/sounds/main menu.mp3` di menu, `game.mp3` di board (`Sfx.play_music`, loop, auto-pilih per scene). Semua tombol otomatis bunyi klik via hook `node_added` (+throttle).
- **Font menu Sriracha (user):** tombol menu pakai `assets/ui/Sriracha.ttf` (fallback `menu_font.ttf` yang isinya identik); font global game tetap `game_font.ttf`.
- **Event pilihan langsung popup (user):** `PLAYER_CHOICE` (Alien Encounter) tidak lagi spawn kartu — popup langsung berisi tombol pilihan + ikut antrean; inspect overlay tidak lagi menutupi popup pilihan. Monster tetap kartu (ancaman fisik board).
- **Intro + ending naratif (user):** intro 6 baris Indonesia (kapal Kargo Om Jarwo, Warp Core sebagai syarat pulang, hint oksigen; delay 0.5 dtk + jeda 0.55/baris); layar game over: flavour menang (rangkai credits+paket) + flavour kalah per alasan + breakdown 3 baris (hari/credits/paket); serangan monster yang menghancurkan Hull pakai alasan sendiri biar dapat flavour monster. Lanjutan: full-English (lihat entri bahasa), em dash dibersihkan dari teks pemain.
- **Tombol game over 2 (user):** Main Lagi + Exit (quit, sama kayak menu).
- **Warning stat + deadline + vignette dinamis + danger + bersih sound (user, 5 item):** (1) segmen O2/Food ikut threshold Hull + kedip pelan saat kritis. (2) `deadline_days` diimplementasikan: kontrak non-SOS non-quest hangus + toast, badge countdown di kartu (`3/5 2.4d`, merah <1 hari). (3) vignette strength 0.65→0.95 saat Hull/O2 kritis. (4) SFX `danger` (2 nada turun) saat serangan monster + alarm 8 dtk saat stat kritis. (5) `scripts/sound/` dihapus total (tak ada referensi).
- **Popup event rapi + tombol gaya UI (user, dari screenshot):** layout kursor dinamis (tinggi deskripsi diukur wrap, panel menyesuaikan, art 200px); `_clear_event_popup` remove_child dulu (OK ganda hilang); tombol OK/pilihan pakai stylebox navy+emas (btn_*.png hanya ikon, tak cocok); panel navy+border emas.
- **Stat bar geser + meta kanan bawah (user, dari screenshot):** bar stat sempat ke tengah-atas lalu dikembalikan ke kiri atas; label Rep/Skor/Quest pindah kanan-bawah font 20 rata kanan; EventLog digeser naik biar tidak tumpuk.
- **Full-English (user):** seluruh teks pemain ke Inggris (~110 file: data cards/recipes/events/packages, semua toast/label/alasan, intro, ending, tombol) via 4 worker paralel + verifikasi grep bersih; komentar kode, plan, dan pesan test sengaja tetap Indonesia. `recipe_resolver` (`Needs:/Missing:`) + debug label ikut diterjemahkan.
- **Feast Meal tanpa Morale (user):** deskripsi jadi "Restores a huge amount of Food (60)" (restore 60 memang tertinggi); sistem Morale tetap out-of-scope v1.
- **Art grup kartu (user):** `art_unit/node/building/tool/material/food.png` sudah dipasang; masih kurang `art_package.png`, `art_event.png`, dan spesifik `art_event_space_monster.png` (monster kini fallback placeholder). Lanjutan: `art_event_space_monster.png` dipasang user (kartu monster ber-art).

---

# BAGIAN E — OPEN QUESTIONS (dari GDD S18, keputusan ditunda)

- **1 Day real-time timer vs "End Day" manual murni? → KEPUTUSAN: full linear (revisi user).** Waktu jalan terus (70 dtk/hari), stat terkuras per-detik, hari berganti otomatis; tombol End Day dihapus, diganti Pause. Gather/produksi/EVA memang sudah real-time sejak awal.
- **Balancing angka pasti (base_value, interval, cost) → KEPUTUSAN: baseline dipertahankan dulu.** Wajib di-tuning setelah playtest pertama; formula scaling A16 sudah menaikkan kesulitan per hari.
- **Defense Turret / combat system → KEPUTUSAN: placeholder.** Tidak ada combat di v1; event DAMAGE_HULL jadi satu-satunya ancaman hull (plus Repair Kit). Dapat ditambah belakangan.
- **Morale system → KEPUTUSAN: opsional, tidak diimplementasi di v1.** Field `morale` tetap ada di GameState, efeknya belum dipakai.
- **Slot O2 Umbilical Station: shared free-for-all vs assign manual? → KEPUTUSAN: shared free-for-all.** Unit yang masuk Zona Angkasa otomatis mengambil slot kosong; slot penuh → drop ditolak + toast.
- **Tether punya limit jarak visual atau bebas sepanjang board? → KEPUTUSAN: bebas sepanjang board.** Tanpa garis visual di v1 (label status saja); garis Line2D bisa ditambah di polish.
- **Recharge Portable O2 Tank: butuh Power/waktu vs instan? → KEPUTUSAN: v1 konsumsi harian saja.** `tank_duration_days` dikurangi tiap End Day saat unit di angkasa; isi ulang = equipp portable tank baru (belum ada recipe — tambah nanti saat balancing).
- **Zona Kapal: slot cap tetap vs expand otomatis? → KEPUTUSAN: tanpa cap di v1.** Kartu bebas ditumpuk/tersebar di zona kapal.
- **Visual transisi pindah sektor: reset Node lama vs tambah area baru? → KEPUTUSAN: belum ada pindah sektor di v1.** Sektor hanya jadi tujuan paket; unlock via reputation.

---

*Plan.md v3 — di-sync dengan GDD v2 (sumber: Downloads\GDD_Space_Salvage.md). Referensi internal menggunakan penomoran A# (A0–A18).*