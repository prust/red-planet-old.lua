-- Generic red planet game engine
-- Initially for space shooters, then top-down shooters & eventually platformer shooters

-- IDEAS:
-- Up to 5 players (4 controllers + keyboard/mouse)
-- healing
-- shot energy that deplets & recharges
-- shield energy that depletes & recharges
-- enemy fire in bursts
-- Collectables (keys/doors, but custom text/images?)
-- Parameterized enemy types (turrets vs moving; speeds, shot intervals)
-- Win state (get to end w/ required collectables?)
-- Mini-map
-- fog/discovered state
-- turret-type enemies that don't move
-- heat-seeking bullets/missiles
-- intelligent aiming enemies (take into account your speed & aim where you'll be)

bump = require 'libs/bump'
sti = require 'libs/sti'
anim8 = require 'libs/anim8'
baton = require 'libs/baton'

local entities = {}
local map, world, level
local player_quads, shot_quad, enemy_shot_quad
local win_w, win_h
local spritesheet
local shot_src
local bullet_speed = 10
local turret_bullet_speed = 8 -- 4=med; 8=hard
local player_speed = 7
local enemy_speed = 4 -- 2=med; 4=hard
local enemy_starting_health = 1
local scale = 0.8

local PLAYER = 1
local BULLET = 2
local TURRET = 3
local ENEMY_BULLET = 4

local players

-- this slows the game; only run it when you're ready to drop into debugging
-- require("mobdebug").start()

function love.load()
  love.window.setMode(0, 0) -- 0 sets to width/height of desktop
  -- nearest neighbor makes player look ugly at most rotations
  -- BUT if I turn it off & do anti-aliasing, then I need 1px padding around sprites!
  love.graphics.setDefaultFilter('nearest') 
  win_w, win_h = love.graphics.getDimensions()
  spritesheet = love.graphics.newImage('images/spritesheet.png')
  player_quads = {
    love.graphics.newQuad(5 * 16, 0, 16, 16, spritesheet:getDimensions()),
    love.graphics.newQuad(6 * 16, 0, 16, 16, spritesheet:getDimensions())
  }
  turret_quad = love.graphics.newQuad(9 * 16, 0, 16, 16, spritesheet:getDimensions())
  shot_quad = love.graphics.newQuad(8 * 16, 0, 2, 2, spritesheet:getDimensions())
  enemy_shot_quad = love.graphics.newQuad(8 * 16, 1 * 16, 2, 2, spritesheet:getDimensions())
  love.graphics.setBackgroundColor(0.15, 0.15, 0.15)

  local joysticks = love.joystick.getJoysticks()
  local num_players = #joysticks
  if num_players == 0 then
    num_players = 1
  end
  players = {}
  for i=1, num_players do
    local player = {
      x = 0,
      y = 0,
      dx = 0,
      dy = 0,
      w = 16,
      h = 16,
      rot = 0,
      quad = player_quads[i],
      type = PLAYER,
      health = 3,
      input = baton.new({
        controls = {
          move_left = {'key:a', 'axis:leftx-', 'button:dpleft'},
          move_right = {'key:d', 'axis:leftx+', 'button:dpright'},
          move_up = {'key:w', 'axis:lefty-', 'button:dpup'},
          move_down = {'key:s', 'axis:lefty+', 'button:dpdown'},
          
          -- TODO: add mouse-aiming to baton library
          aim_left = {'axis:rightx-', 'key:left'},
          aim_right = {'axis:rightx+', 'key:right'},
          aim_up = {'axis:righty-', 'key:up'},
          aim_down = {'axis:righty+', 'key:down'},
      
          shoot = {'mouse:1', 'axis:triggerright+', 'key:ralt'},
          zoom_in = {'button:rightshoulder'},
          zoom_out = {'button:leftshoulder'},
          quit = {'key:escape'}
        },
        pairs = {
          move = {'move_left', 'move_right', 'move_up', 'move_down'},
          aim = {'aim_left', 'aim_right', 'aim_up', 'aim_down'}
        },
        joystick = joysticks[i]
      })
    }
    table.insert(players, player)
  end

  -- https://www.leshylabs.com/apps/sfMaker/
  -- w=Square,W=22050,f=1045,_=-0.9,b=0,r=0.1,s=52,S=21.23,z=Down,g=0.243,l=0.293
  shot_src = love.audio.newSource('sfx/shot.wav', 'static')

  pcall(playRandomSong)

  -- find-and-replace regex to transform .tsv from http://donjon.bin.sh/d20/dungeon/index.cgi
  -- into lua tiled format: [A-Z]+\t -> "0, "
  level = "maps/level-2.lua"
  
  world = bump.newWorld(64)
  map = sti(level, { "bump" })
  map:bump_init(world)
  
  for k, object in pairs(map.objects) do
    if object.name == "player_spawn" then
      for i=1, #players do
        local player = players[i]
        player.x = object.x
        player.y = object.y
        world:add(player, player.x, player.y, player.w, player.h) -- w/h should be about 1.6 based on current scaling
        table.insert(entities, player)
      end
    elseif object.name == "enemy" then
      local enemy = {
        x = object.x,
        y = object.y,
        dx = 0,
        dy = 0,
        w = 16,
        h = 16,
        health = enemy_starting_health,
        quad = turret_quad,
        rot = 0,
        type = TURRET
      }
      world:add(enemy, enemy.x, enemy.y, enemy.w, enemy.h) -- 2 isn't exactly right, scaling is weird; 1.6 is more accurate?
      table.insert(entities, enemy)
    end
  end
  
  map:removeLayer("Objects")

  love.window.setFullscreen(true)
  love.mouse.setVisible(false)
end

function playRandomSong()
  local songs = {
    'celldweller_tim_ismag_tough_guy.wav',
    'celldweller_just_like_you.wav',
    'celldweller_into_the_void.wav',
    'celldweller_end_of_an_empire.wav',
    'celldweller_down_to_earth.wav'
  }
  
  math.randomseed(os.time())
  local song = songs[math.random(#songs)]
  local song_src = love.audio.newSource('music/' .. song, "stream")
  song_src:play()
end

local turret_timer = 0
function love.update(dt)
  turret_timer = turret_timer + dt
  map:update(dt)

  -- Handle turret shooting every 1 seconds
  if turret_timer >= 1 then
    turret_timer = turret_timer - 1
    for i = 1, #entities do
      if entities[i].type == TURRET then
        local turret = entities[i]

        -- rudimentary calc to determine which player is closest
        local dist_closest_player = 1000 / scale
        local closest_player = nil
        for i = 1, #players do
          local dist = math.abs(players[i].x - turret.x) + math.abs(players[i].y - turret.y)
          if dist < dist_closest_player then
            dist_closest_player = dist
            closest_player = players[i]
          end
        end

        if closest_player and dist_closest_player < 1000 / scale then
          turret.rot = math.atan2(closest_player.y - turret.y, closest_player.x - turret.x)

          turret.dx = enemy_speed * math.cos(turret.rot)
          turret.dy = enemy_speed * math.sin(turret.rot)

          local bullet = {
            x = turret.x,
            y = turret.y,
            dx = turret_bullet_speed * math.cos(turret.rot),
            dy = turret_bullet_speed * math.sin(turret.rot),
            w = 2,
            h = 2,
            quad = enemy_shot_quad,
            type = ENEMY_BULLET -- TODO: use bitwise operations to add drawable/damageable/etc
          }
          table.insert(entities, bullet)

          world:add(bullet, bullet.x, bullet.y, bullet.w, bullet.h)

          if (shot_src:isPlaying()) then
            shot_src:stop()
          end
          shot_src:play()
        end
      end
    end
  end

  -- Hande player input & player shooting
  for i=1, #players do
    local player = players[i]
    player.input:update()
    local aim_x, aim_y = player.input:get('aim')
    if aim_x ~= 0 or aim_y ~= 0 then
      player.rot = math.atan2(aim_y, aim_x)
    end

    player.dx, player.dy = player.input:get('move')
    player.dx = player.dx * player_speed
    player.dy = player.dy * player_speed

    if player.input:pressed('zoom_in') then
      scale = scale * 1.5
    end

    if player.input:pressed('zoom_out') then
      scale = scale / 1.5
    end

    if (player.input:pressed('quit')) then
      love.event.quit()
    end
    
    if player.input:pressed('shoot') then
      -- make shooting sound
      if (shot_src:isPlaying()) then
        shot_src:stop()
      end
      shot_src:play()

      -- create bullet going in the right direction
      local bullet = {
        x = player.x,-- + player.w/2,
        y = player.y,-- + player.h/2,
        dx = bullet_speed * math.cos(player.rot),
        dy = bullet_speed * math.sin(player.rot),
        w = 2,
        h = 2,
        quad = shot_quad,
        type = BULLET
      }
      table.insert(entities, bullet)

      -- TODO: due to scaling it should be more than / 2...
      world:add(bullet, bullet.x, bullet.y, bullet.w, bullet.h)
    end
  end

  -- Handle collisions & removals
  -- remove all entities *after* iterating, so we don't mess up iteration
  local entity_ix_to_remove = {}
  local entities_to_remove = {}

  for i = 1, #entities do
    local entity = entities[i]
    local cols
    entity.x, entity.y, cols = world:move(entity, entity.x + entity.dx, entity.y + entity.dy, getCollType)

    for j = 1, #cols do
      local col = cols[j]
      if entity.type == BULLET then
        if col.other.type == TURRET then
          col.other.health = col.other.health - 1
          if col.other.health <= 0 then
            local turret_ix = indexOf(entities, col.other)
            table.insert(entity_ix_to_remove, turret_ix)
            table.insert(entities_to_remove, col.other)
          end
        end

        if col.other.type ~= PLAYER then
          table.insert(entity_ix_to_remove, i)
          table.insert(entities_to_remove, entity)
          break
        end
      elseif entity.type == ENEMY_BULLET then
        if col.other.type == PLAYER then
          col.other.health = col.other.health - 1
          if col.other.health <= 0 then
            local player_ix = indexOf(entities, col.other)
            table.insert(entity_ix_to_remove, player_ix)
            table.insert(entities_to_remove, col.other)

            -- also remove player from players table
            table.remove(players, indexOf(players, col.other))
          end
        end
        
        if col.other.type ~= TURRET then
          table.insert(entity_ix_to_remove, i)
          table.insert(entities_to_remove, entity)
          break
        end
      end
    end
  end

  -- iterate backwards over indexes so removal doesn't mess up other indexes
  table.sort(entity_ix_to_remove)
  for i = #entity_ix_to_remove, 1, -1 do
    table.remove(entities, entity_ix_to_remove[i])
  end

  -- have to remove items from the world later (here) as well
  for i = 1, #entities_to_remove do
    world:remove(entities_to_remove[i])
  end
end

function indexOf(table, item)
  for i = 1, #table do
    if table[i] == item then
      return i
    end
  end
end

function getCollType(item, other)
  if other.name == 'player_spawn' or item.name == 'player_spawn' or other.name == 'enemy' or item.name == 'enemy' then
    return nil
  elseif item.type == BULLET or other.type == BULLET or item.type == ENEMY_BULLET or other.type == ENEMY_BULLET then
    return "cross"
  else
    return "slide"
  end
end

function love.draw()
  love.graphics.setColor( 255,255,255,255 )
  local sum_player_x = 0
  local sum_player_y = 0
  for i = 1, #players do
    sum_player_x = sum_player_x + players[i].x
    sum_player_y = sum_player_y + players[i].y
  end
  tx = -(sum_player_x / #players) + ((win_w/2) / scale)
  ty = -(sum_player_y / #players) + ((win_h/2) / scale)
  map:draw(tx, ty, scale, scale)
  
  love.graphics.setColor(255, 255, 225, 255)
  --love.graphics.scale(sx, sy)
  love.graphics.translate(tx * scale, ty * scale)
  
  local num_turrets = 0
  for i=1, #entities do
    local entity = entities[i]
    -- + entity.w / 2
    -- + entity.h / 2
    -- scale * 
    -- scale *
    love.graphics.draw(spritesheet, entity.quad, scale * (entity.x + entity.w / 2), scale * (entity.y + entity.h / 2), entity.rot or 0, scale, scale, entity.w / 2,  entity.h / 2)
    if entity.type == TURRET then
      num_turrets = num_turrets + 1
    end
  end
  -- map:bump_draw(world, tx, ty, sx, sy) -- debug collision map

  love.graphics.reset()
  love.graphics.setBackgroundColor(0.15, 0.15, 0.15) -- have to reset bgcolor after a reset()
  local str = "FPS: " .. tostring(love.timer.getFPS()) .. ', Enemies: ' .. tostring(num_turrets)
  local health = {}
  for i=1, #players do
    table.insert(health, players[i].health)
  end
  str = str .. ', Lives: ' .. table.concat(health, ",")
  love.graphics.print(str, 10, 10)
end

function love.resize(w, h)
  map:resize(w*8, h*8)
  win_w = w
  win_h = h
end
