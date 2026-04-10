# 🔧 NBRP Job Crafting

Standalone job-based crafting system built for QBCore using ox_lib, ox_target, and ox_inventory.

---

## ✨ Features

* 🛠️ Create crafting stations in-game
* 👮 Job & grade locked stations
* 📦 ox_inventory + qb fallback support
* 🎯 ox_target interaction zones
* ⏳ Progress bars & animations
* 🧠 Built-in admin crafting builder
* 💾 Auto-saving stations (JSON)

---

## 📦 Dependencies

* ox_lib
* ox_target
* qb-core

---

## 📁 Installation

1. Download or clone this repo
2. Place in your `resources` folder

Structure:

```
nbrp-jobcrafting/
├── client/
├── server/
├── data/
├── fxmanifest.lua
├── config.lua
```

3. Add to your `server.cfg`:

```
ensure ox_lib
ensure ox_target
ensure qb-core
ensure nbrp-jobcrafting
```

---

## ⚙️ Usage

Use command:

```
/craftbuilder
```

* Create stations
* Add recipes
* Set ingredients & rewards
* Assign jobs & grades

---

# Preview

<img width="334" height="704" alt="create_ui" src="https://github.com/user-attachments/assets/05e29622-7daa-4a32-9cc1-acbb0adda596" /> <img width="569" height="1043" alt="recipie_build" src="https://github.com/user-attachments/assets/48f1d470-416a-4d8e-9029-81e86e710d91" />


---
## 📌 Notes

* Stations are saved in:

  ```
  data/stations.json
  ```
* Supports multiple crafting stations
* Fully scalable system

---

## 🔒 Permissions

Admins are defined in:

```
Config.AdminGroups
```

---

## 👑 Credits

Created by **M1Wolves**

---

## 📜 License

MIT License
