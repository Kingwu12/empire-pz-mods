-- Empire Performance - Inventory Scan Throttle
-- DISABLED: conflicts with Proximity Inventory's container scan
-- Proximity Inventory already handles its own update rate efficiently
-- Removing this patch to prevent the getEffectiveCapacity nil errors

print("[EmpirePerf] Inventory throttle disabled (Proximity Inventory conflict avoided).")
