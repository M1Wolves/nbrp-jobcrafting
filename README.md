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
