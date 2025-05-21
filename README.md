# Doctrine: Open Platoon Strategy

**Doctrine: Open Platoon Strategy** is a free, open-source real-time tactics game inspired by *Company of Heroes*. Built using **Godot 4.3**, it offers a fully moddable framework for creating dynamic RTS scenarios with customizable factions, squads, and battlefield logic.

> **📄 Full Developer Documentation:**  
> [View here on Google Docs](https://docs.google.com/document/d/1SwRlM_GhbNZIEyF8fDz9QOazDvM4ad_Nv64w7ouSOMM/edit?usp=sharing)

---

## 🎮 Features

- 🎖️ **Tactical Platoon-Level Combat** — Focus on infantry tactics with data-driven unit definitions.
- 🧩 **Modular Game Design** — Easily extend or override units, buildings, and abilities via `.tres` files.
- 🎥 **Smooth RTS Camera** — Middle-mouse drag to pan, scroll to zoom, and survey the battlefield in style.
- 🖱️ **Click & Command Interface** — Left-click to select, right-click to issue movement orders.
- 🛠️ **Plug-in Modding System** — Built-in support for user mods with no need to modify core files.

---

## 🚀 How to Play
Install Godot 4.3+

Clone the repo:

```bash
Copy
Edit
git clone https://github.com/yourusername/doctrine.git
cd doctrine
```
Open the project in Godot (godot .)

Run scenes/SandBox.tscn to test camera movement, selection, and infantry orders.

---

## 🗂️ Project Structure

```bash
doctrine/
├── core/              # Shared logic and helper scripts
├── data/              # Units, factions, abilities (.tres resources)
├── mods/              # Player-made overrides (same structure as /data)
├── scenes/            # In-game logic and 3D object scenes
├── ui/                # HUD icons, cursors, markers
└── README.md
