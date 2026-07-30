# On-screen touch control art

From Xelu's "Free Controller & Keyboard Prompts" pack (Nicolae Berbece /
Those Awesome Guys), public domain under CC0:
https://thoseawesomeguys.com/prompts/

256px Nintendo Switch set, renamed for src/core/TouchControls.lua:
d-pad (neutral + per-direction highlight), A, B, plus (START) and
minus (SELECT).

Also required (same pack/style), for the shoulder/trigger/hotkey row and
the dual sticks -- TouchControls:init soft-fails the *entire* overlay if
any one of these is missing, so all ten must be present together:

  l1.png, r1.png       -- shoulder buttons (L1/R1)
  l2.png, r2.png        -- triggers (L2/R2)
  hotkey1.png ... hotkey4.png  -- H1-H4, touch-only hotkey slots
  leftstick.png, rightstick.png -- analog stick caps
