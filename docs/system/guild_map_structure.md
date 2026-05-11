# Guild Map Structure

## Purpose

This document records the current map-building policy for the adventurer guild scene.
It is intended as onboarding context for future Codex chats and for manual Godot editor work.

## Current Approach

The guild map uses a **single background image plus individual Sprite2D props**.

- The floor, walls, beams, entrance, and black outside area are part of one background image.
- Furniture and interactive objects are placed as separate nodes in `Guild.tscn`.
- Collision is handled separately from visuals.
- The player still moves on a 64 px grid.

This approach was chosen because wall/floor TileMap generation did not produce side walls reliably enough, while a single background image gives a better guild interior composition.

## Main Files

- Scene: `res://scenes/main/Guild.tscn`
- Scene script: `res://scripts/main/Guild.gd`
- Player movement/collision logic: `res://scripts/player/Player.gd`
- Background image: `res://assets/backgrounds/guild_background_full_v1_960x720.png`
- Furniture spritesheet: `res://assets/props/guild/guild_furniture_spritesheet_v1.png`
- Individual furniture sprites: `res://assets/props/guild/guild_furniture_v1_parts/`
- Scaled furniture sprites for current placement: `res://assets/props/guild/guild_furniture_v1_scaled/`
- Furniture manifest: `res://assets/props/guild/guild_furniture_v1_manifest.json`

## Scene Layout Policy

`Guild.tscn` currently keeps the visual layout directly in the scene.

The background is displayed with:

- `BlackBackground`: large black `ColorRect` behind the room.
- `Background`: `Sprite2D` using `guild_background_full_v1_960x720.png`.

The old placeholder `ColorRect` floor/walls remain in the scene but are hidden.
They should not be used as the final visual style.

## Furniture and Props

Functional or visible props should be placed as individual nodes.

Current important props:

- `QuestBoard`
- `Counter`
- `Table1`
- `Stairs2F`
- `Chair1` to `Chair4`
- `Barrel1` and `Barrel2`
- `WallBlocks`

Guideline:

- Use `Sprite2D` or a small parent `Node2D` for visual-only props.
- Use `StaticBody2D` or `Node2D` with `CollisionShape2D` plus `blocking_props` for blocked props.
- Keep prop positions editable in `Guild.tscn`; manual placement in the Godot editor is expected.

## Movement Blocking

Movement is grid-based, not physics-driven.

`Player.gd` checks `blocking_props` in `can_move()` through `_is_blocked_by_prop()`.

Blocking behavior:

- If a `blocking_props` node has `CollisionShape2D` children, their rectangular shape areas are used.
- If no usable `CollisionShape2D` exists, the node's own grid position is used as a fallback.

This means Godot physics collision alone is not enough.
For grid movement blocking, the node must be in the `blocking_props` group.

## Current Blocking Rules

Blocked:

- `Counter`
- `Table1`
- `Stairs2F`
- `Barrel1`
- `Barrel2`
- Wall blocks under `WallBlocks`

Not blocked:

- `Chair1` to `Chair4`

The chairs are visual-only on purpose. The player can walk through them unless this is changed later.

## Wall Blocks

Wall collision is represented by invisible blocking nodes under `WallBlocks`.

Current wall block structure:

- `BackWallBlock`
- `LeftWallBlock`
- `RightWallBlock`
- `FrontWallLeftBlock`
- `FrontWallRightBlock`

The front wall is split into left and right blocks so the bottom-center entrance remains open.

When adjusting wall collision:

- Move the relevant `*WallBlock` node position.
- Adjust the corresponding `RectangleShape2D_wall_*_block` size.
- Do not block the `GuildExit` tile unless intentionally changing exit behavior.

## Interactive Objects

The quest board interaction is handled in `Guild.gd`.

Current behavior:

- Pressing the interact action near `QuestBoard` opens `QuestBoardUI`.
- `GuildExit` returns the player to the village when the player's grid position reaches the exit grid.

If the visual positions of `QuestBoard` or `GuildExit` are moved significantly, update their node positions and test the grid interaction range.

## Notes for Future Work

- Furniture placement is still provisional and should be tuned by eye in Godot.
- Collision rectangles are intentionally simple and may need manual adjustment.
- If more large props are added, place them in `blocking_props` and add `CollisionShape2D`.
- If props should be walked through, do not add them to `blocking_props`.
- If a prop is both interactive and blocking, keep interaction logic separate from movement blocking.

