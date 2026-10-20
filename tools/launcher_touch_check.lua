local T=require("src.import.LauncherTouch")
local file=assert(io.open('src/import/RomImporter.lua','rb'));local src=file:read('*a');file:close()
local start=assert(src:find('function RomImporter:_updateSlotDrag()',1,true))
local finish=assert(src:find('-- SAVE SLOT card:',start,true))
local code='local RomImporter={};local function clamp(x,a,b)return math.max(a,math.min(b,x))end;local function inside(r,x,y)return r and x>=r.x and y>=r.y and x<=r.x+r.width and y<=r.y+r.height end;'
 ..src:sub(start,finish-1)..';return RomImporter'
local RI=assert((loadstring or load)(code))()
local n=0
local function check(v,msg)assert(v,msg);n=n+1 end
local function ui()
 local u={_s=1,android=true,touchPollable=false,_pageMax=1000,pageScroll=0,
  clicks=0,steps=0,slotScroll={},_mx=50,_my=150}
 u.wheelmoved=RI.wheelmoved;u._updateSlotDrag=RI._updateSlotDrag
 function u:_pointerHold()return false,self._my,self._mx end
 function u:mousepressed()self.clicks=self.clicks+1 end
 function u:_stepSetting()self.steps=self.steps+1 end
 function u:_selectSlot()self.selected=true end
 return u
end
-- Controls that used to execute immediately (Play, edit, delete, sidebar,
-- coin shop, import) all go through the same release-only entry point.
for _,control in ipairs({'Play','Edit','Delete','Sidebar','Shop','Import'})do
 local u=ui();T.pressed(u,1,50,150);check(u.clicks==0,control..' acted on press')
 T.moved(u,1,50,100);T.released(u,1,50,100)
 check(u.pageScroll==50 and u.clicks==0,control..' activated during scrolling')
end
local u=ui();T.pressed(u,1,50,150);T.released(u,1,52,153)
check(u.clicks==1,'stationary tap activates exactly once without touch polling')
u=ui();T.pressed(u,1,50,150);T.released(u,1,50,90)
check(u.clicks==0 and u.pageScroll==60,'fast swipe without move events cancels tap')
u=ui();T.pressed(u,1,50,150);T.moved(u,1,80,150);T.released(u,1,50,150)
check(u.clicks==0,'drag back to origin remains cancelled')
u=ui();T.pressed(u,1,50,150);T.pressed(u,2,60,150);T.released(u,1,50,150)
check(u.clicks==0,'multi-touch cancels selection')
u=ui();u._pageMax=0;u.tab='mods';u._modMax=500;u.modScroll=0
T.pressed(u,1,50,150);T.moved(u,1,50,100);T.released(u,1,50,100)
check(u.modScroll==50 and u.clicks==0,'inner mod list scrolls')
u=ui();u._tabBand={0,500,0,50};u._tabMax=400;u.tabScroll=0
T.pressed(u,1,150,25);T.moved(u,1,100,25);T.released(u,1,100,25)
check(u.tabScroll==50 and u.clicks==0,'horizontal tab strip scrolls')
u=ui();u.settingsOpen=true;u.settingsDrawerRect={x=0,y=0,width=300,height=500};u._settingsMax=500;u.settingsScroll=0
T.pressed(u,1,50,150);T.moved(u,1,50,100);T.released(u,1,50,100)
check(u.settingsScroll==50 and u.pageScroll==0,'drawer scroll stays in drawer')
u=ui();function u:mousepressed()self._settingsPress={entry={},dir=1,y0=150,moved=false}end
T.pressed(u,1,50,150);T.released(u,1,50,150)
check(u.steps==1 and not u._settingsPress,'legacy settings row resolves on native release')
u=ui();function u:mousepressed()self._slotPress={version='emerald',id=1,y0=150}end
T.pressed(u,1,50,150);T.released(u,1,50,150)
check(u.selected and not u._slotPress,'legacy slot row resolves on native release')
check(not u._touchResolving and not u._touchGesture,'gesture state cleared after tap')
print('Launcher touch gestures: '..n..' checks passed')
