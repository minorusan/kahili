# Investigation: PickSlotsSpawner InstantiateSlots NullReference
## TLDR
This looks like a production-only NullReference in `PickSlotsSpawner.InstantiateSlots` when spawning pick slots. The code assumes the resolved prefab contains a `PickSlot` component; if it does not, the factory returns null and the next line dereferences it, crashing the async slot-spawn loop.
## Risk Assessment
Moderate: the crash is non-fatal to the app but breaks the Pick Minigame popup for affected users and blocks progression until the popup is reopened or cached data resets.
## Release Branch
v3.34.6
## Release Version
3.34.6
## Error Summary
`NullReferenceException` in `Powerof.Popups.Logic.PickSlotsSpawner+<InstantiateSlots>d__15.MoveNext`, occurring during pick slot instantiation when opening the minigame popup.
## Root Cause
`InstantiateSlots` resolves a prefab via `ResolveSlotPrefab` and then calls `_pickSlotFactory.Create(prefab, _parentRect)`. If the resolved prefab does not include a `PickSlot` component (e.g., `_uiElementPrefab` is a plain UI element or a typed prefab missing the script), the factory returns null. The next line dereferences `pick` (`pick.GetComponent<RectTransform>()`), causing the NullReference. There are no guards validating that the prefab actually contains `PickSlot`.
## Affected Code
- `Assets/Scripts/Popups/ViewLogic/PickMiniGame/PickSlotsSpawner.cs` (`InstantiateSlots`, `ResolveSlotPrefab`, `HasAnyPrefab`)
- `Assets/Scripts/Popups/ViewLogic/PickMiniGame/PickSlot.cs` (`PickSlot.Factory.Create` returns null if prefab missing component)
## Suggested Fix
Add explicit validation that resolved prefabs contain `PickSlot` before instantiation, and fail fast with a clear error if they do not. For example:
- In `ResolveSlotPrefab` or `InstantiateSlots`, check `prefab.GetComponent<PickSlot>() != null`; if not, log an error and skip/abort spawning.
- Update `HasAnyPrefab` to require a prefab with `PickSlot` rather than just non-null, so invalid configs are caught earlier.
- Optionally, treat `_uiElementPrefab` as size-only and never use it for instantiation unless it has `PickSlot`.
## Suggested Assignee
AndriyVyshnyuk
