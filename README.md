# Freecam

this Freecam provides smooth camera controls, adjustable FOV, cinematic filters, NPC vehicle driving, vehicle-following cameras, and a locked camera mode for dynamic vehicle shots.

## ✨ Features

- Smooth free camera movement
- Vehicle-follow mode
- Locked camera mode
- AI Drive mode
- Adjustable FOV (Field of View)
- Multiple cinematic filters
- Configurable camera range limits
- Built-in HUD display
- Lightweight and optimized
- Fully configurable settings

---

## 📦 Installation

1. Download this repository.
2. Place the folder inside your server's `resources` directory.
3. Add the resource to your `server.cfg`:

```cfg
ensure pgn_freecam
```

4. Restart your server.

---

## 🎮 Controls

| Control | Action |
|----------|----------|
| `/freecam` | Toggle Freecam |
| Mouse | Look Around |
| W | Move Forward |
| S | Move Backward |
| A | Move Left |
| D | Move Right |
| Space | Move Up |
| E | Move Down |
| Mouse Wheel Up | Zoom In |
| Mouse Wheel Down | Zoom Out |
| F3 | Toggle AI Drive |
| F4 | Toggle Locked Camera |
| F7 | Cycle Filters |
| F8 | Toggle HUD |
| Arrow Left | Roll Camera Left |
| Arrow Right | Roll Camera Right |

---

## 🚗 Vehicle Features

### Vehicle Follow Mode

When activated while driving a vehicle, the camera follows the vehicle's movement and rotation, allowing smooth cinematic tracking shots.

### Locked Camera Mode

Locks the camera position relative to the vehicle for realistic chase-cam and mounted-camera style recordings.

### AI Drive Mode

Allows your character to drive automatically while you focus entirely on camera work.

---

## 🎨 Included Filters

- Cinematic
- Cool
- Trippy
- Warm
- Rage
- Pursuit
- Electric
- Turbo
- Off

---

## ⚙️ Configuration

All settings can be modified in `config.lua`.

### Camera Settings

```lua
MoveSpeed    = 0.07
MaxRange     = 500.0
MinFOV       = 1.0
MaxFOV       = 120.0
ZoomSpeed    = 0.9
DefaultFOV   = 90.0
```

### General Settings

```lua
ActivationCommand       = "freecam"
HelpersVisibleByDefault = true
FreezeOnActivate        = false
```

### HUD Position

```lua
HudTop  = "16vh"
HudLeft = "1vw"
```

---

## 🔧 Requirements

- FiveM Server
- GTA V
- Cerulean FXServer Build

---

## 📋 Resource Information

| Property | Value |
|-----------|--------|
| Framework | Standalone |
| Game | GTA V |
| FX Version | Cerulean |
| Version | 1.0.0 |

---

## 🐛 Support

If you encounter a bug or have a feature request, please open a ticket in my discord!
https://discord.gg/QsgZJJdhhZ

---

## 📜 License

This resource is released free of charge.

You may:
- Use it on your server.
- Modify it for personal use.

You may not:
- Re-upload without credit.
- Resell the resource.
- Claim the resource as your own work.

---

## ❤️ Credits

Created by **Lyla**

Built for the FiveM roleplay and content creation community.
