-- Markdown: an agent's reply as lines with the game's color codes.
local T = ...
local eq, same = T.eq, T.same

-- Part of the Agent Chat companion addon, which takes Forever++'s ns from ForeverPlusPlusCompanion.
local ns = {}
T.env.ForeverPlusPlusCompanion = function() return ns end
T.load("../ForeverPlusPlus_AgentChat/Lib/Markdown", ns)
local M = ns.Markdown

same(M.Lines("plain text"), { "plain text" }, "markdown: plain text as is")
same(M.Lines("a\n\nb\n"), { "a", " ", "b" }, "markdown: a blank line keeps its space, the last newline doesn't")
same(M.Lines("## Heading ##"), { "|cffffd100Heading|r" }, "markdown: heading in gold, marks gone")
same(M.Lines("some **bold** words"), { "some |cffffffffbold|r words" }, "markdown: bold in white")
same(M.Lines("run `go test` now"), { "run |cffa8dca8go test|r now" }, "markdown: code in green")
same(M.Lines("`**not bold**`"), { "|cffa8dca8**not bold**|r" }, "markdown: code is kept as written")
same(M.Lines("- one\n  * two"), { "  \226\128\162 one", "    \226\128\162 two" }, "markdown: bullets, indented")
same(M.Lines("**Tested:**"), { "|cffffffffTested:|r" }, "markdown: bold at the start isn't a bullet")
same(M.Lines("see [docs](https://x.io/a)"), { "see |cff71d5ffdocs|r |cff9d9d9d(https://x.io/a)|r" },
    "markdown: link text, address in gray")
same(M.Lines("> quoted"), { "|cff9d9d9d  quoted|r" }, "markdown: quote in gray")
same(M.Lines("---"), { "|cff9d9d9d----------|r" }, "markdown: rule")
same(M.Lines("```lua\nlocal x = 1\n\nprint(x)\n```"), { "|cffa8dca8local x = 1|r", " ", "|cffa8dca8print(x)|r" },
    "markdown: a code block, fences gone")
same(M.Lines("```\n**x** `y`\n```"), { "|cffa8dca8**x** `y`|r" }, "markdown: no marks inside a code block")
same(M.Lines("| a | b |\n|---|:--:|\n| 1 | 2 |"), { "|| a || b ||", "|| 1 || 2 ||" },
    "markdown: table rows as written, divider left out")
same(M.Lines("a|cffff0000red"), { "a||cffff0000red" }, "markdown: the text's own | can't color anything")
same(M.Lines("1. first"), { "1. first" }, "markdown: numbered items as written")
eq(#M.Lines(""), 1, "markdown: empty text is one blank line")
same(M.Lines("a\r\nb"), { "a", "b" }, "markdown: Windows line ends")
