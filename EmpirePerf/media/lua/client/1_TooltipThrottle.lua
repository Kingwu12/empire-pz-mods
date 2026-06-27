-- Empire Performance - Tooltip Throttle (DISABLED)
-- Original version hooked ISToolTip.render / ISToolTipInv.render and skipped
-- drawing on throttled frames. PZ UI is immediate-mode: skipping a frame's
-- render means the tooltip is not drawn that frame, which causes visible
-- flashing/flicker on hover. Vanilla tooltips redraw every frame by design and
-- the cost is negligible, so there is no safe way to "throttle" them.
-- Left as a no-op so the EmpirePerf mod stays intact without breaking tooltips.

print("[EmpirePerf] Tooltip throttle disabled (was causing hover flicker).")
