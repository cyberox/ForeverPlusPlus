-- Secret: what counts as readable, text, a number, or true while values can be secret.
local T = ...
local ns, eq, game = T.ns, T.eq, T.game

eq(ns.IsReadable(5), true, "readable without issecretvalue")
game.secret = "secret"
eq(ns.IsReadable("secret"), false, "secret is unreadable")
eq(ns.IsText("a"), true, "text")
eq(ns.IsText(""), true, "empty text")
eq(ns.IsText("", true), false, "empty text when it must not be")
eq(ns.IsText(5), false, "a number isn't text")
eq(ns.IsText(nil), false, "nil isn't text")
eq(ns.IsText("secret"), false, "secret isn't text")
eq(ns.IsNumber(5), true, "a number")
eq(ns.IsNumber("5"), false, "text isn't a number")
game.secret = 7
eq(ns.IsNumber(7), false, "a secret number isn't readable")
game.secret = "secret"
eq(ns.IsTrue(true), true, "true is true")
eq(ns.IsTrue(false), false, "false isn't true")
eq(ns.IsTrue("secret"), false, "secret isn't surely true")
eq(ns.IsTrueOrSecret(false), false, "false is off")
eq(ns.IsTrueOrSecret(nil), false, "nil is off")
eq(ns.IsTrueOrSecret("secret"), true, "secret may be true")
game.secret = nil
