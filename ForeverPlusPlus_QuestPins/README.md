# Forever++ Quest Pins

A plugin for [Forever++](../ForeverPlusPlus): it adds a **Quest Pins** module to Forever++, so it shows on
Forever++'s Modules page with native options, profiles and tooltips. It needs Forever++ and is listed only
while the **QuestieDB** addon is installed.

It uses Forever++'s public API only (`ForeverPlusPlusAPI.v1.RegisterModule` and `GetPluginKit()`, see
[docs/api.md](../docs/api.md), "Plugins"), never its private tables. Like Agent Chat it ships apart from
Forever++'s releases.

Ported from [BetterQuestPins](CurseForge project 1786993) by Wouter
(GPL-3.0-or-later). Quest data: QuestieDB by Lawgon and TheCrux_BB. `Blacklist.lua` is generated from
Questie's quest blacklist (GPLv3) by `tools/gen-blacklist.lua`.
