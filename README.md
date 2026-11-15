# whip_dealership

Simon's car lot: walk up to Simon, browse the cars with their pictures, pay cash or from a bank account, and the car
is waiting at the lot, yours to keep.

- **Needs:** whip_core.
- **Install:** it comes in the `[whip]` folder, and `ensure [whip]` starts it. Nothing to add to server.cfg, no SQL.
- **What Simon sells:** every car in whip_core's vehicle catalog that has a picture, in a class he sells (no boats,
  planes, helicopters, trains, military or bicycles: `Config.SellableClasses`). The catalog is whip_core's: the 930
  cars in `whip_core/server/vehicle_catalog_list.lua`, each with its picture in whip_assets_4. To add a car, see the
  top of that file.
- **Prices:** by class (`Config.ClassPrice`), with a price per model where one is written (`Config.ModelPrice`). The
  server works out the price; a player's game never says it.
- **Where:** Simon's spot and where a bought car appears are `Config.Salesman` and `Config.Delivery` in
  `config.lua`.
- **Manage Keys:** Simon's second option lists the cars you own, with their pictures. Pick one for three choices:
  **Make new key** puts another key in your pockets, **Disable previous keys** (hold E) makes every key made before
  stop fitting, wherever it is, and **Active keys** shows how many keys fit the car now. It is built on a prompt menu
  filled when it opens (see `client/main.lua`) and whip_core's `GiveVehicleKey`, `ChangeVehicleLocks` and
  `CountVehicleKeys`.
