# 🕵️‍♂️ HdnS — 3D Hide & Seek Multi-Agent Reinforcement Learning

<div align="center">

[![Godot Engine](https://img.shields.io/badge/Godot%20Engine-4.x-478CBF?style=for-the-badge&logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Reinforcement Learning](https://img.shields.io/badge/Reinforcement%20Learning-Deep%20Q--Learning-8A2BE2?style=for-the-badge&logo=openai&logoColor=white)](https://en.wikipedia.org/wiki/Q-learning#Deep_Q-learning)
[![Architecture](https://img.shields.io/badge/Architecture-Tri--Window%203D-00D2FF?style=for-the-badge&logo=windowsterminal&logoColor=white)](https://godotengine.org/)
[![Arena Scale](https://img.shields.io/badge/Arena%20Scale-40x40%20(80m%20%C3%97%2080m)-FF6B35?style=for-the-badge)](https://github.com/)
[![License](https://img.shields.io/badge/License-MIT-32CD32?style=for-the-badge)](LICENSE)

*An autonomous, adversarial 3D multi-agent hide-and-seek simulation built in Godot 4, featuring pure GDScript Deep Q-Networks (DQN), teacher-guided exploration, dynamic role swapping, procedural BSP facility generation, and a real-time multi-window desktop interface.*

[Features](#-key-features) • [Architecture](#-system-architecture) • [Reinforcement Learning](#-reinforcement-learning-system) • [Controls](#-controls--hotkeys) • [Getting Started](#-getting-started) • [Directory Structure](#-directory-structure)

</div>

---

## 📖 Overview

**HdnS** is an asymmetric, competitive multi-agent simulation where two autonomous neural network agents play hide-and-seek inside an endless series of procedurally generated facilities. 

Rather than relying on pre-scripted behavior trees or external Python bindings, **HdnS runs complete forward and backward propagation directly inside Godot 4 using custom pure GDScript tensor operations**. Each agent possesses dual deep neural network brains (one for hiding and one for seeking), sensory raycast arrays, heuristic teacher policies, and dynamic role-swapping mechanisms with preserved memory.

The simulation pops out **three native desktop windows**:
1. **Central Spectator Arena**: 3D bird's-eye and director-tracked free-roam camera overlooking the facility.
2. **Left Agent Monitor**: Live first-person POV viewport, orbiting 3D holographic showcase, and real-time neural thought terminal for Agent 1.
3. **Right Agent Monitor**: Live first-person POV viewport, orbiting 3D holographic showcase, and real-time neural thought terminal for Agent 2.

---

## ⚡ Key Features

- **🧠 Dual-Brain Deep Q-Networks (DQN)**:
  - Custom fully-connected neural network implementation in pure GDScript (51,973 parameters per brain).
  - Experience Replay Buffer (5,000 capacity) with batch SGD and Polyak target network stabilization.
  - Asymmetric roles: Agents maintain specialized brains for both **Hiding** (stealth, cover-seeking, break-LoS) and **Seeking** (BFS sweep, visual tracking, strike lunges).

- **🔄 Asymmetric Role Swapping**:
  - Rounds terminate upon capture or after a **3-minute countdown timer**.
  - Roles swap dynamically upon match completion (Hider $\leftrightarrow$ Seeker).
  - Agents retain their learned Q-values across procedural map regeneration, enabling continuous lifelong co-evolution.

- **🏢 Procedural 40×40 BSP Tactical Facility**:
  - Binary Space Partitioning (BSP depth 6) carving 16–24 interconnected rooms and corridors across an 80m × 80m arena.
  - Tactical interior cover obstacles (2×2 pillar clusters and server rack barricades) for breaking Line-of-Sight.
  - Cybernetic LED wall rims (`MultiMeshInstance3D`) and 10-palette architectural ceiling lighting with dynamic shadows.

- **👁️ 15-Ray Omnidirectional Vision Cone**:
  - 140° field-of-view raycast array detecting wall proximity, opponent distance, and line-of-sight obstruction.
  - Forward hunter spotlight for Seeker with 28-meter high-intensity search cone.

- **🎓 Teacher-Guided Tactical Advisor Policy**:
  - Replaces pure random epsilon noise with tactical heuristics (BFS room patrols, LoS pursuit, corner escape, barricade flanking).
  - Smooth epsilon decay ($1.0 \to 0.05$) gradually transitions agents from expert guidance to neural intuition.

- **🖥️ Multi-Window Desktop Interface**:
  - Three independent OS desktop windows running simultaneously with GPU-accelerated SubViewports.
  - Real-time Q-value action breakdown (`NORTH`, `SOUTH`, `WEST`, `EAST`, `STAY`), tactical intent logs, and loss curves.

- **⏱️ Accelerated Training Modes**:
  - Supports 1×, 5×, 20×, and 100× simulation speeds for rapid offline training.
  - Stepped 2×2 heatmap sampling (400 evaluation points) guaranteeing locked 60+ FPS performance.

---

## 🏗️ System Architecture

```mermaid
graph TD
    subgraph Godot Desktop [Tri-Window Desktop Runtime]
        MW[Main Spectator Window\n3D Arena + Free Camera]
        W1[Agent 1 Window\nPOV + 3D Showcase + Thoughts]
        W2[Agent 2 Window\nPOV + 3D Showcase + Thoughts]
    end

    subgraph Simulation Orchestration [Turn & Map Management]
        TM[TurnManager\nTime Limit: 3m | Speed: 1x-100x]
        MG[MapGenerator\n40x40 BSP | Cover | Lighting]
        TA[TacticalAdvisor\nHeuristic Teacher Guidance]
    end

    subgraph Agents & Neural Brains [AIAgent Multi-Brain Architecture]
        A1[Agent 1: Alpha\nState: 40-dim vector]
        A2[Agent 2: Omega\nState: 40-dim vector]
        B1_H[Hider Brain\n51,973 Params]
        B1_S[Seeker Brain\n51,973 Params]
        B2_H[Hider Brain\n51,973 Params]
        B2_S[Seeker Brain\n51,973 Params]
    end

    MW --> TM
    TM --> MG
    TM --> A1
    TM --> A2
    TA -.-> A1
    TA -.-> A2
    A1 <--> W1
    A2 <--> W2
    A1 --> B1_H
    A1 --> B1_S
    A2 --> B2_H
    A2 --> B2_S
```

---

## 🧬 Reinforcement Learning System

### 1. Neural Network Specification
Each agent brain contains a feedforward Deep Q-Network:
- **Input Layer**: 40 dimensions
  - `[0..1]`: Normalized agent grid coordinate $(X / W, Y / H)$
  - `[2..3]`: Relative vector to opponent $(\Delta X / W, \Delta Y / H)$
  - `[4..33]`: 15 vision rays $\times$ 2 features (normalized distance & hit classification)
  - `[34..37]`: 4 adjacent wall occupancy indicators (North, South, East, West)
  - `[38]`: Episode time remaining ratio $(t_{\text{left}} / t_{\text{max}})$
  - `[39]`: Active role indicator ($0.0 = \text{Seeker}, 1.0 = \text{Hider}$)
- **Hidden Layers**:
  - Linear $(40 \to 128)$ + ReLU activation
  - Linear $(128 \to 64)$ + ReLU activation
  - Linear $(64 \to 32)$ + ReLU activation
- **Output Layer**: 5 Q-values
  - Action 0: `MOVE NORTH`
  - Action 1: `MOVE SOUTH`
  - Action 2: `MOVE WEST`
  - Action 3: `MOVE EAST`
  - Action 4: `HOLD POSITION`
- **Total Parameters**: **51,973 weights & biases** per neural network.

### 2. Reward Engineering Matrix

| Condition | Seeker Reward | Hider Reward | Description |
| :--- | :---: | :---: | :--- |
| **Capture / Tag** | `+100.0` | `-100.0` | Seeker tags Hider (distance $\le 1$ tile or $2.4\text{m}$ proximity). |
| **Timeout (3 Min)** | `-100.0` | `+100.0` | Hider successfully avoids capture for full 180 seconds. |
| **Line-of-Sight Break** | `-0.20` | `+0.40` | Hider breaks visual contact behind cover pillars or walls. |
| **Line-of-Sight Contact**| `+0.35` | `-0.25` | Seeker spots and maintains direct visual contact with Hider. |
| **Distance Closing** | `+0.15` | `-0.15` | Seeker decreases shortest-path BFS distance to target. |
| **Distance Widening** | `-0.10` | `+0.20` | Hider widens escape margin from Seeker. |
| **Step Tax** | `-0.05` | `+0.05` | Discourages idling; incentivizes fast hunting. |
| **Illegal Move / Wall** | `Masked` | `Masked` | Action masking invalidates illegal moves before decision execution. |

---

## 🎮 Controls & Hotkeys

### Spectator & Director Camera

| Key / Input | Action | Description |
| :---: | :--- | :--- |
| `W` `A` `S` `D` | Fly Movement | Move the spectator camera through 3D space. |
| `Right Click` (Hold) | Look Around | Free-look mouse rotation (captures cursor while held). |
| `Mouse Wheel` | Flight Speed | Adjust flight velocity (0.1× to 10×). |
| `Shift` / `Ctrl` | Descend / Sprint | Accelerate flight speed by 2.5×. |
| `Space` / `E` | Ascend | Fly vertically upwards. |
| `Q` | Descend | Fly vertically downwards. |
| `F` | **Track Seeker** | Director auto-tracking chase camera locked on the hunter. |
| `G` | **Track Hider** | Director auto-tracking camera observing evasion tactics. |
| `H` | **Overview** | Smooth pan back to top-down 45° facility overview. |
| `C` | Mouse Lock | Toggle permanent mouse capture mode. |
| `ESC` | Release Mouse | Free cursor for multi-window management. |

### Simulation & Training Controls

| Key | Action | Description |
| :---: | :--- | :--- |
| `1` | **1× Speed** | Real-time speed ($0.15\text{s}$ per turn) for visual observation. |
| `2` | **5× Speed** | Fast-forward match play. |
| `3` | **20× Speed** | High-speed training. |
| `4` | **100× Speed** | Ultra-speed batch iteration (thousands of turns/minute). |
| `P` | **Pause / Resume** | Freeze simulation state to inspect Q-values. |
| `TAB` | **Toggle HUD** | Show/hide stats overlay, timer, and minimap. |
| `R` | **Reroll Map** | Regenerates procedural facility (preserves Q-tables). |
| `R` (Press 5×) | **Factory Reset** | Wipes learned weights & resets neural brains to baseline. |

---

## 📁 Directory Structure

```
HdnS/
├── project.godot                     # Godot 4.x engine configuration
├── README.md                         # Project documentation & reference
├── scenes/
│   └── main.tscn                     # Root scene (WorldEnvironment, DirectionalLight)
└── scripts/
    ├── main.gd                       # Main orchestrator, multi-window & lighting setup
    ├── ai_agent.gd                   # 3D agent character, sensory rays, state builder
    ├── agent_body_builder.gd         # Procedural 3D morphing models (Hunter vs Stalker)
    ├── agent_window.gd               # Sub-window manager (POV camera, 3D showcase, thoughts)
    ├── free_camera.gd                # Spectator camera with F/G/H director tracking
    ├── hud.gd                        # CanvasLayer HUD, round timer, Q-value heatmap minimap
    ├── map_generator.gd              # 40x40 procedural BSP map, cover obstacles & lights
    ├── neural_network.gd             # GDScript tensor network, matrix matmul, backprop SGD
    ├── rl_brain.gd                   # DQN brain, replay memory, action masking, target sync
    ├── tactical_advisor.gd           # Expert heuristic teacher policy & LoS raycasting
    └── turn_manager.gd               # Turn scheduler, spatial catch detection, role swapping
```

---

## 🚀 Getting Started

### Prerequisites

- **[Godot Engine 4.2+](https://godotengine.org/download)** (Standard Edition, 64-bit).
- Compatible with **Linux, Windows, and macOS**.
- Multi-monitor setup recommended (for left/right agent thought terminals), but runs smoothly on single monitors.

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-username/HdnS.git
   cd HdnS
   ```

2. **Launch with Godot**:
   - Open Godot Engine.
   - Click **Import** $\to$ Browse to the `HdnS` directory $\to$ Select `project.godot`.
   - Click **Import & Edit**.
   - Press **F5** (or click the **Play** button in the top right) to launch the simulation.

3. **Or run via Terminal**:
   ```bash
   # Run directly with Godot CLI
   godot --path . scenes/main.tscn

   # Run headlessly for benchmark verification
   godot --path . --headless scenes/main.tscn
   ```

---

## 🔬 How the Multi-Window System Works

When launched, `main.gd` calls:
```gdscript
get_viewport().gui_embed_subwindows = false
```
Godot spawns three operating-system-level windows:
- **Main Viewport**: Displays the full 40×40 arena with dynamic lighting, shadows, and the global HUD.
- **Agent 1 Window** (`Vector2i(main_pos.x - 470, main_pos.y)`): A dedicated $450 \times 800$ terminal showing Agent 1's POV camera, an orbiting showcase model, and real-time live decision telemetry.
- **Agent 2 Window** (`Vector2i(main_pos.x + main_size.x + 10, main_pos.y)`): Positioned directly to the right of the main display with Agent 2's respective POV and telemetry.

When roles swap after a catch or round timeout, each window automatically updates its color themes, title banners, and 3D showcase meshes.

---

## 📊 Telemetry & HUD Breakdown

```
╔═══════════════════════════════════════════════════════════════╗
║                   ⏱ ROUND TIME REMAINING                    ║
║                          02:47                                ║
╚═══════════════════════════════════════════════════════════════╝
 ═══ HIDE & SEEK RL ═══
 Episode: 14         Time Left: 02:47 / 03:00
 Turns Taken: 220    Speed: 1x

 ── Agent 1 [HIDER] ──
   Score: 400 PTS  (W:4 | L:2)
   ε: 0.1240 | Ep Rew: 32.4
   Avg Rew: 14.8 | Loss: 0.00312

 ── Agent 2 [SEEKER] ──
   Score: 200 PTS  (W:2 | L:4)
   ε: 0.0810 | Ep Rew: -12.1
   Avg Rew: 8.5  | Loss: 0.00194
```

- **Top-Center Banner**: 3-minute survival clock that turns orange under 60s and flashing red under 30s.
- **Bottom-Right Heatmap Minimap**: Visualizes the Seeker's neural Q-value landscape across all walkable tiles (green indicates high-reward search directions; red indicates penalized zones).

---

## 🛠️ Customization & Tuning

All parameters are exposed in clean GDScript constants:

| Parameter | File | Default | Description |
| :--- | :--- | :---: | :--- |
| `map_width`, `map_height` | `scripts/main.gd` | `40, 40` | Grid tile dimensions (each tile is $2.0\text{m}$). |
| `EPISODE_TIME_LIMIT` | `scripts/turn_manager.gd` | `180.0` | Maximum round duration in seconds (3 mins). |
| `VISION_RAYS` | `scripts/ai_agent.gd` | `15` | Number of raycasts in the vision fan. |
| `VISION_RANGE` | `scripts/ai_agent.gd` | `24.0` | Maximum sensory raycast distance in meters. |
| `MEMORY_CAPACITY` | `scripts/rl_brain.gd` | `5000` | Size of experience replay buffer. |
| `BATCH_SIZE` | `scripts/rl_brain.gd` | `32` | Minibatch size sampled for SGD training. |
| `LEARNING_RATE` | `scripts/rl_brain.gd` | `0.001` | Adam/SGD learning rate for weight optimization. |

---

## 📄 License

This project is licensed under the **MIT License** — feel free to use, modify, and distribute for personal, academic, or commercial research.

---

<div align="center">
Made with ❤️ using <b>Godot Engine 4</b> & <b>Reinforcement Learning</b>
</div>
