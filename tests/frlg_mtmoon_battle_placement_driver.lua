-- Visible regression for FireRed battle-platform placement.  The cave backdrop
-- contains edge detail on rows above its platforms; those rows must not pull
-- trainer or Pokemon sprites left toward the opponent health box.
return function(game)
  local U = require("tests.drivers.util")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local Gen3Battle = require("src.battle.Gen3Battle")

  local function save()
    local s=U.freshSave(game)
    local mon=Pokemon.new(game.data,"MEWTWO",100)
    mon.moves={{id="PSYCHIC",pp=99,maxPp=99}}
    s.party={mon}
    return s
  end
  local function run(tag,px,py)
    U.teleport(game,"MAP_G01_N03",px,py,"up")
    U.tap(game,"up"); U.wait(2); U.tap(game,"a")
    local intro,mons=false,false
    for frame=1,12000 do
      local top=game.stack:top()
      if getmetatable(top)==BattleState then
        if not intro and (top.introSlide or 0)==0 and top.showEnemyTrainer then
          local p=Gen3Battle.platforms(top)
          assert(p.opponent.x == 175.5,
            ("FireRed opponent platform center drifted to %s"):format(p.opponent.x))
          assert(p.player.x == 63.5,
            ("FireRed player platform center drifted to %s"):format(p.player.x))
          local img=top:picImage(top.trainerPic)
          local tx,ty=Gen3Battle.picPlacement(top,{isPlayer=false},img,nil,1)
          U.log(tag,"platforms",p.opponent.x,p.opponent.y,p.player.x,p.player.y,
            "trainer",tx,ty,"hud",Gen3Battle.hudPlace(game.data.constants,"opponent",32))
          assert(U.shot(game,"ngshots/mtmoon_"..tag.."_trainer.png"))
          intro=true
        end
        if not mons and top.phase=="menu" and not top.showEnemyTrainer then
          local ei=top:picImage(top.enemy.sprite)
          local pi=top:picImage(top.player.sprite)
          local ex,ey=Gen3Battle.picPlacement(top,top.enemy,ei,top.enemy.sprite,1)
          local px2,py2=Gen3Battle.picPlacement(top,top.player,pi,top.player.sprite,1)
          U.log(tag,"mons",ex,ey,px2,py2)
          assert(U.shot(game,"ngshots/mtmoon_"..tag.."_mons.png"))
          mons=true
        end
        if intro and mons then
          U.log("PASS visual capture",tag)
          while game.stack:top() do game.stack:pop() end
          return
        end
        if frame%8==1 then U.tap(game,"a") else U.wait(1) end
      else
        if frame%8==1 then U.tap(game,"a") else U.wait(1) end
      end
    end
    error("battle visual capture timed out "..tag)
  end
  U.wait(20); save()
  run("rocket",37,22)
  run("scientist",13,12)
  love.event.quit(0)
end
