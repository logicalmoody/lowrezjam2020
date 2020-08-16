-- yolo solo
-- a hot beans game
-- cal moody and reagan burke
-- lowrezjam 2020

--[[ flag reference
	sprite
		0: ledges
		1: solid ground
		2: jug
		3: crimp
		4: crack
--]]

--[[ input reference
	left: 0
	right: 1
	up: 2
	down: 3
	o: 4
	x: 5
--]]

player = nil
g_force = 0.2
classes = {}
actors = {}
particles = {}
coroutines = {}
start_time = 0
level_loaded = false
end_time = 0
musicoff = false
resetbuttonpressed = false

--vector functions (turns out order matters)
function vec2(x, y)
	local v = {
		x = x or 0,
		y = y or 0
	}
	setmetatable(v, vec2_meta)
	return v
end

function vec2conv(a)
	return vec2(a.x, a.y)
end

vec2_meta = {
	__add = function(a, b)
		return vec2(a.x+b.x,a.y+b.y)
	end,
	__sub = function(a, b)
		return vec2(a.x-b.x,a.y-b.y)
	end,
	__div = function(a, b)
		return vec2(a.x/b,a.y/b)
	end,
	__mul = function(a, b)
		return vec2(a.x*b,a.y*b)
	end
}

function vdot(v1, v2)
	return (v1.x * v2.x) + (v1.y * v2.y)
end

function vmag(v)
	local m = max(abs(v.x), abs(v.y))
	local vec = {x = 0, y = 0}
	vec.x = v.x / m
	vec.y = v.y / m
	return sqrt((vec.x * vec.x) + (vec.y * vec.y)) * m
end

function vnorm(vec)
	local v = vec2()
	v = vec/vmag(vec)
	return v
end

function vdist(v1, v2)
	return sqrt(((v2.x-v1.x)*(v2.x-v1.x))+((v2.y-v1.y)*(v2.y-v1.y)))
end

cam = {
	-- todo: use the offset here
	pos = vec2(0, 0-1280),
	lerp = 0.15,
	update = function(self, track_pos)
		-- lerp follow
		local p = self.pos
		local half = 28
		local third = 39
		p.x += (track_pos.x - p.x - half) * self.lerp
		p.y += (track_pos.y - p.y - third) * self.lerp
		-- use flr to prevent camera jitter
		camera(flr(p.x), flr(p.y))
		self.pos = p
	end
}

-- sprite, base class
c_sprite = {
	sprite = nil,
	sprites = {
		default = {
			number = 0,
			hitbox = {o = vec2(0, 0), w = 8, h = 8}
		}
	},
	flip = false,
	name = "sprite",
	parent = nil,
	state = "rest",
	p = vec2(0, 0),
	v = vec2(0, 0),
	new = function(self, o)
		local o = o or {}
		setmetatable(o, self)
		self.__index = self
		self.sprite = o.sprites.default
		return o
	end,
	move = function(self)
		self.p += self.v
	end,
	draw = function(self)
		spr(self.sprite.number, self.p.x, self.p.y, 1, 1, self.flip)
	end
}
add(classes, c_sprite:new({}))

--state machine system
c_state = {
	name = "state",
	parent = nil,
	currentstate = nil,
	states = {
		default = {
			name = "rest",
			rules = {
				function(self)
					--put transitional logic here
					return "rest"
				end
			}
		}
	},
	--Why do we use o.states.default instead of self.states.default (157)
	new = function(self, o)
		local o = o or {}
		setmetatable(o, self)
		self.__index = self
		o.currentstate = o.states.default
		return o
	end,
	transition = function(self)
		local name = self.currentstate.name
		local rules = #self.currentstate.rules
		local i = 1
		while (name == self.currentstate.name) and i <= rules do
			local var = self.currentstate.rules[i](self.parent)
			if (var) name = var
			i += 1
		end
		self.currentstate = self.states[name]
	end
}

-- animation, inherites from sprite
-- rewrite this in the future, post-jam
c_anim = c_sprite:new({
	name = "animation",
	fr = 15,
	frames = {1},
	fc = 1,
	playing = false,
	playedonce = false,
	starttime = 0,
	currentframe = 1,
	loopforward=function(self)
		if self.playing == true then
			--add 2 to the end to componsate for flr and 1-index
			self.currentframe = flr(time() * self.fr % self.fc) + 1
		end
		return self.frames[self.currentframe]
	end,
	playonce = function(self)
		notimplimentedyet = 0
	end
	--[[loopbackward = function(self)
		if self.playing == true then
			self.currentframe = self.fc - (flr(time() * self.fr % self.fc) + 1)
		end
	end,
	stop = function(self)
		playing = false
	end--]]
})
add(classes, c_anim:new({}))

-- object, inherits from sprite
c_object = c_sprite:new({
	name="object",
	grounded = false,
	pass_thru = false,
	pass_thru_pressed_at = 0,
	was_pass_thru_held = false,
	pass_thru_time = 0.2,
	gonna_hit_ledge = false,
	update = function(self)	end,
	move = function(self)
		local p, v = self.p, self.v
		p.y += v.y
		while ceil_tile_collide(self) do p.y += 1 end
		while floor_tile_collide(self) do p.y -= 1 end

		if v.y >= 0 and not self.pass_thru and (ledge_below(self) or self.gonna_hit_ledge) then
			-- we know we're about to hit a ledge so we need to re-enter this condition next frame
			self.gonna_hit_ledge = true
			while floor_ledge_collide(self) do p.y -= 1 end
		else
			self.gonna_hit_ledge = false
		end

		p.x += v.x
		while right_tile_collide(self) do p.x -= 1 end
		while left_tile_collide(self) do p.x += 1 end

		-- keep inside level boundary
		while calc_edges(self).l < 0 do p.x += 1 end
		local level_width = #level.screens
		while calc_edges(self).r > level_width*64 do p.x -= 1 end

		if floor_tile_collide(self) then
			p.y = flr(p.y) -- prevent visually stuck in ground
		end
		self.grounded = on_ground(self) or (on_ledge(self) and not self.pass_thru and v.y >= 0)
		-- sprite orientation
		if v.x > 0 then self.flip = false
		elseif v.x < 0 then self.flip = true end
		self.p = p
		self.v = v
	end,
	collide = function(self, other)
		local personal_space, their_space = calc_edges(self), calc_edges(other)
		return personal_space.b > their_space.t and
			personal_space.t < their_space.b and
			personal_space.r > their_space.l and
			personal_space.l < their_space.r
	end
})
add(classes, c_object:new({}))

c_pickup = c_object:new({
	name = "pickup",
	active = true,
	respawn_time = 5,
	picked_up_at = nil,
	draw = function(self)
		if self.active then
			c_object.draw(self)
		end
	end,
	die = function(self)
		self.picked_up_at = time()
		self.active = false
	end
})
add(classes, c_pickup:new({}))

c_granola = c_pickup:new({
	name = "granola",
	update = function(self)
		if self.picked_up_at == nil or time() - self.picked_up_at > self.respawn_time then
			self.active = true
		end
	end,
	sprites = {
		default = {
			number = 42,
			hitbox = {o = vec2(0, 0), w = 8, h = 8 }
		}
	}
})
add(classes, c_granola:new({}))

c_chalkhold = c_object:new({
	name = "chalkhold",
	sprites = {
		default = {
			number = 55,
			hitbox = {o = vec2(0, 0), w = 8, h = 8 }
		}
	},
	anims = {
		drip = c_anim:new({
			frames = {55, 56, 57},
			fc = 3,
			fr = 2
		})
	},
	activated = false,
	anim = function(self)
		if self.activated then
			self.anims.drip.playing = true
			frame = self.anims.drip:loopforward()
			--frame = self.anims.drip.frames[self.anims.drip.currentframe]
			--spr(self.sprite.number, self.p.x, self.p.y, 1, 1, self.flip)
		elseif player.has_chalk then
			frame = 37
		elseif not player.has_chalk then
			frame = 38
		end
		spr(frame, self.p.x, self.p.y, 1, 1, self.flip)
	end,
	draw = function(self)
		self:anim()
	end
})
add(classes, c_chalkhold:new({}))

c_chalk = c_pickup:new({
	name = "chalk",
	sprites = {
		default = {
			number = 58,
			hitbox = {o = vec2(0, 0), w = 8, h = 8 }
		}
	}
})
add(classes, c_chalk:new({}))

-- Music manager
c_jukebox = c_object:new({
	songs = {0, 6, 8, 23, 35},
	currentsong = -1,
	playing = true,
	startplayingnow = function(self, songn, f, chmsk)
		if self.playing then
			if currentsong != self.songs[songn] then
				music(self.songs[songn], f, chmsk)
			end
			currentsong = self.songs[songn]
		end
	end,
	stopplaying = function(self)
		self.playing = false
		music(-1, 300)
		currentsong = -1
	end
})
add(classes, c_jukebox:new({}))

-- entity, inherits from object
c_entity = c_object:new({
	name = "entity",
	spd = 1,
	topspd = 1,
	move = function(self)
		-- gravity
		if not self.holding then
			if not self.grounded or self.jumping then
				self.v.y += g_force
				self.v.y = mid(-999, self.v.y, 5) -- clamp
			else
				self.v.y = 0
			end
		end
		c_object.move(self)
	end,
	die = function(self)
		del(actors, self)
	end
})
add(classes, c_entity:new({}))

-- player, inherits from entity
c_player = c_entity:new({
	sprites = {
		default = {
			number = 1,
			hitbox={ o = vec2(0, 0), w = 8, h = 8 }
		}
	},
	anims = nil,
	finished = false,
	movable = false,
	statemachine = nil,
	name = "player",
	spd = 0.5,
	jump_force = 2.5,
	currentanim = "default",
	topspd = 2, -- all player speeds must be integers to avoid camera jitter
	jumped_at = 0,
	num_jumps = 0,
	max_jumps = 1,
	squatting = false,
	jumping = false,
	can_jump = true,
	jump_after_hold_window = 0.3, --300ms
	jump_delay = 0.5,
	jump_cost = 25,
	jump_pressed = false,
	jump_newly_pressed = false,
	dead = false,
	on_crack = false,
	on_crimp = false,
	on_jug = false,
	holding_pos = vec2(0, 0),
	last_held = 0,
	was_holding = false,
	hold_wiggle = 3,
	hold_spd = 0.5,
	hold_topspd = 0.75,
	holding = false,
	holding_cooldown = 0.3, -- 300ms
	crimp_drain = 1,
	on_chalkhold = false,
	chalkhold = nil,
	has_chalk = false,
	stamina = 100,
	max_stamina = 100,
	stamina_regen_rate = 3,
	stamina_regen_cor = nil,
	add_stamina = function(self, amount)
		self.stamina = mid(0, self.stamina + amount, self.max_stamina)
	end,
	input = function(self)
		local v = self.v
		if self.dead then return end -- no zombies
		if self.holding then
			local new_vel = vec2(0, 0)
			if btn(2) then
				new_vel.y = mid(-self.hold_topspd, v.y - self.hold_spd, self.hold_topspd)
			elseif btn(3) then
				new_vel.y = mid(-self.hold_topspd, self.v.y + self.hold_spd, self.hold_topspd)
			else -- decay
				v.y *= 0.5
				if abs(v.y) < 0.2 then v.y = 0 end
			end
			if btn(1) then
				new_vel.x = mid(-self.hold_topspd, self.v.x + self.hold_spd, self.hold_topspd)
			elseif btn(0) then
				new_vel.x = mid(-self.hold_topspd, self.v.x - self.hold_spd, self.hold_topspd)
			else -- decay
				v.x *= 0.5
				if abs(v.x) < 0.2 then v.x = 0 end
			end

			local new_pos = vec2(self.p.x+new_vel.x, self.p.y+new_vel.y)
			if abs(vdist(new_pos, self.holding_pos)) <= self.hold_wiggle or self.on_crack then
				v = new_vel
			else
				v.y *= 0.5
				if abs(v.y) < 0.2 then v.y = 0 end
				v.x *= 0.5
				if abs(v.x) < 0.2 then v.x = 0 end
			end
		else
			-- left/right movement
			if self.movable and btn(1) then
				self.v.x = mid(-self.topspd, self.v.x + self.spd, self.topspd)
			elseif self.movable and btn(0) then
				self.v.x = mid(-self.topspd, self.v.x - self.spd, self.topspd)
			else -- decay
				v.x *= 0.5
				if abs(v.x) < 0.2 then v.x = 0 end
			end
			-- pass thru
			if btn(3) then
				if not self.was_pass_thru_pressed then
					self.pass_thru_pressed_at = time()
				end
				self.was_pass_thru_pressed = true
				self.squatting = true
			else
				self.was_pass_thru_pressed = false
				self.squatting = false
			end
			self.pass_thru = time() - self.pass_thru_pressed_at > self.pass_thru_time and self.was_pass_thru_pressed
		end

		-- jump
		if self.grounded then self.num_jumps = 0 end

		-- only jump on a new button press
		if btn(5) then
			if not self.jump_pressed then
				self.jump_newly_pressed = true
			else
				self.jump_newly_pressed = false
			end
			self.jump_pressed = true
		else
			self.jump_pressed = false
			self.jump_newly_pressed = false
		end

		local jump_window = time() - self.jumped_at > self.jump_delay
		local can_jump_after_holding = self.grounded or time() - self.last_held < self.jump_after_hold_window
		self.can_jump = self.num_jumps < self.max_jumps and
			jump_window and
			can_jump_after_holding and
			self.stamina > 0 and
			not self.holding and
			self.jump_newly_pressed
		if not jump_window then self.jumping = false end

		if self.can_jump and btn(5) then
			self.jumped_at = time()
			self.num_jumps += 1
			self.jumping = true
			v.y = 0 -- reset dy before using jump_force
			v.y -= self.jump_force
			self:add_stamina(-self.jump_cost)
			sfx(3, -1, 0, 14)
		end

		-- shake the hud if you run out of stamina
		if self.stamina <= 0 and btn(5) and self.jump_newly_pressed then
			hud:shakebar()
		end

		-- drain stamina
		if self.on_crimp and self.holding then
			self:add_stamina(-self.crimp_drain)
		end

		-- hold
		local can_hold_again = (time() - self.last_held) > self.holding_cooldown
		local on_any_hold = self.on_jug or self.on_crimp or self.on_crack
		if btn(4) then
			if can_hold_again then
				if on_any_hold then
					if self.holding == false then
						-- first grabbed, stick position and reset jump
						self.holding_pos = vec2(self.p.x, self.p.y)
						self.was_holding = true
						v = vec2(0, 0)
						self.num_jumps = 0
					end
					self.holding = true
				elseif self.on_chalkhold and self.has_chalk then
					self.chalkhold.activated = true
					sfx(5)
					self.has_chalk = false
				end
			end
		else
			self.holding = false
		end
		if not on_any_hold then
			self.holding = false
		end
		if self.was_holding and not self.holding then
			self.last_held = time()
			self.was_holding = false
		end
		self.v = v
	end,
	regen_stamina = function(self)
		while self.stamina < self.max_stamina do
			if self.grounded then
				self:add_stamina(self.stamina_regen_rate)
			end
			yield()
		end
	end,
	new = function(self, o)
		local o = o or {}
		setmetatable(o, self)
		self.__index = self
		o.statemachine = c_state:new({
			name = "states",
			states = {
				default = {
					name = "default",
					rules = {
						function(p)
							if p.finished then
								return "finished"
							elseif p.holding then
								return "hold"
							elseif p.squatting then
								return "squat"
							elseif abs(p.v.x) > 0.01 and p.holding == false and p.grounded == true then
								return "walk"
							elseif p.v.y > 0 and p.grounded == false then
								return "falling"
							elseif (p.v.y < 0) then
								 return "jumping"
							 end
						end
					}
				},
				walk = {
					name = "walk",
					rules = {
						function(p)
							if (p.finished) return "finished"
							if (abs(p.v.x) <= 0.01 and p.holding == false) return "default"
							if p.holding then
								sfx(6, -2)
								sfx(6, -1, 0, 7)
								return "hold"
							end
							if (p.v.y < 0 and p.grounded) return "jumping"
							if (p.v.y > 0.01) return "falling"
							return "walk"
						end
					}
				},
				jumping = {
					name = "jumping",
					rules = {
						function(p)
							if (p.finished) return "finished"
							if (p.holding) then
								sfx(6, -2)
								sfx(6, -1, 0, 7)
								return "hold"
							end
							if(p.v.y == 0) return "default"
							if (p.v.y > 0) return "falling"
						end
					}
				},
				hold = {
					name = "hold",
					rules = {
						function(p)
							if (p.finished) return "finished"
							if (p.v.y < 0 and p.holding == false) return "falling"
							if (abs(p.v.x) <= 0.01 and p.holding == false) return "default"
							if (abs(p.v.x) >= 0.01 and p.holding == true) return "shimmyx"
							if (abs(p.v.y) >= 0.01 and p.holding == true) return "shimmyy"
							if (not p.holding) return "default"
							return "hold"
						end
					}
				},
				finished = {
					name = "finished",
					rules = {
						function(p)
							p.movable = false
							return "finished"
						end
					}
				},
				shimmyx = {
					name = "shimmyx",
					rules = {
						function(p)
							if (p.finished) return "finished"
							if (abs(p.v.x) < 0.01 and p.holding) return "hold"
							if (not p.holding) return "default"
							if (not p.holding and p.v.y < 0.0) return "falling"
							return "shimmyx"
						end
					}
				},
				shimmyy = {
					name = "shimmyy",
					rules = {
						function(p)
							if (p.finished) return "finished"
							if (abs(p.v.y) < 0.01 and p.holding) return "hold"
							if (not p.holding) return "default"
							if (not p.holding and p.v.y < 0.0) return "falling"
							return "shimmyy"
						end
					}
				},
				squat = {
					name = "squat",
					rules = {
						function(p)
							if btn(3) then
								p.movable = false
							else
								p.movable = true
							end
							if (p.holding) return "hold"
							if (p.v.y > 0.1) return "falling"
							if (not p.squatting) return "default"
						end
					}
				},
				falling = {
					name = "falling",
					rules = {
						function(p)
							p.movable = true
							if (p.finished) return "finished"
							if (p.grounded) and p.v.y <= 4.5 then
								local particle2 = smokepuff:new({
									p = player.p,
									v = vec2(-2, 0),
									dt = 1
								})
								local particle = smokepuff:new({
									p = player.p,
									v = vec2(2, 0),
									dt = 1
								})
								sfx(1, -1, 0, 18)
								add(particles, particle)
								add(particles, particle2)
								return "default"
							elseif (p.grounded) and p.v.y >= 4.5 then
								for i = 1, 15, 1 do
									add(particles, c_particle:new({
										p = player.p + vec2(4, 8),
										v = vec2(rnd(32)-16,
										rnd(16)-16),
										c = 14,
										life = flr(rnd(15)),
										damp = rnd(0.5),
										g = 9.8,
										dt = 0.25
									}))
									sfx(9)
								end
								player:die()
								return "dead"
							elseif (p.holding) then
								sfx(6, -2)
								sfx(6, -1, 0, 7)
								return "hold"
							elseif (p.v.y < 0) then
									add(particles, airjump:new({p = player.p, v = player.v * -10}))
									--spr(16, player.p.x + 4, player.p.y + 10)
								return "jumping"
							end
						end
					}
				},
				dead = {
					name = "dead",
					rules = {
						function(p)
							p.dead = true
							return "dead"
						end
					}
				}
			}
		})
		o.anims = {
			walk = c_anim:new({
				frames = {2, 3, 4},
				fc = 3
			}),
			hold = c_anim:new({
				frames = {5, 6, 7},
				fc = 3
			}),
			shimmyx = c_anim:new({
				frames = {8, 9, 10},
				fc = 3
			}),
			falling = c_anim:new({
				frames = {11, 12},
				fc = 2
			})
		}
		return o
	end,
	move = function(self)
		self:input()
		-- stamina
		if self.stamina < self.max_stamina then
			self.stamina_regen_cor = cocreate(self.regen_stamina)
		end
		if self.stamina_regen_cor and costatus(self.stamina_regen_cor) != "dead" then
			coresume(self.stamina_regen_cor, self)
		else
			self.stamina_regen_cor = nil
		end
		self:anim()
		c_entity.move(self)
	end,
	hold_collide = function(self)
		for i = 0, 7 do
			for j = 0, 7 do
				local px = self.p.x+i
				local py = self.p.y+j
				if jug_tile(px, py) then
					return "jug"
				elseif crimp_tile(px, py) then
					return "crimp"
				elseif crack_tile(px, py) then
					return "crack"
				end
			end
		end
	end,
	collide = function(self, actor)
		if c_entity.collide(self, actor) then
			if actor.name == "granola" then
				-- only act if has respawned
				if actor.active then
					self.stamina = self.max_stamina
					sfx(2, -2)
					sfx(2, -1, 0, 9)
					actor:die()
				end
			elseif actor.name == "chalk" then
				if not self.has_chalk then
					self.has_chalk = true
					sfx(4, -1, 0, 10)
					actor:die()
					del(actors, actor)
				end
			elseif actor.name == "chalkhold" then
				if actor.activated then
					self.on_jug = true
				elseif not actor.activated then
					self.on_chalkhold = true
					self.chalkhold = actor
				end
			elseif actor.name == "goal" then
				if nextlvl == nil or costatus(nextlvl) == 'dead' then
					nextlvl = cocreate(actor.next_level)
					player.finished = true
					coresume(nextlvl, actor)
					add(coroutines, nextlvl)
				end
			end
		end
	end,
	anim = function(self)
		--self:determinestate()
		local frame = 1
		local state = self.state
		local sprites = self.sprites
		local number = self.sprites.default.number
		self.statemachine.transition(self.statemachine)
		state = self.statemachine.currentstate.name

		-- todo: find a way to save the sprites and hitboxes to the states?
		if state=="default" then
			--self.sprite=sprites.default
			number = 1
		elseif state=="sit" then
			self.sprite=sprites.sit
		--assign state, make animation play, set frame number to existing sprite hitbox
		elseif state=="walk" then
			self.anims.walk.playing = true
			number = self.anims.walk:loopforward()
			--number = self.anims.walk.frames[self.anims.walk.currentframe]
		elseif state == "hold" then
			number = 5
			if (self.jump_newly_pressed) hud:shakehand()
		elseif state == "shimmyx" then
			self.anims.shimmyx.playing = true
			number = self.anims.shimmyx:loopforward()
			--number = self.anims.shimmyx.frames[self.anims.shimmyx.currentframe]
		elseif state == "shimmyy" then
			self.anims.hold.playing = true
			number = self.anims.hold:loopforward()
			--number = self.anims.hold.frames[self.anims.hold.currentframe]
		elseif state=="jumping" then
			number = 2
		elseif state == "falling" then
			self.anims.falling.playing = true
			number = self.anims.falling:loopforward()
			--frame = self.anims.falling.frames[self.anims.falling.currentframe]
			--number = frame
		elseif state == "dead" then
			number = 14
		elseif state == "finished" then
			number = 106
		elseif state == "squat" then
			number = 15
		end
		self.state = state
		self.sprites.default.number = number
	end
})
add(classes, c_player:new({}))

c_hud = c_object:new({
	baro = vec2(0, 0),
	hando = vec2(0, 0),
	draw = function(self)
		corneroffset = cam.pos + self.baro
		rectfill(
			corneroffset.x,
			corneroffset.y,
			cam.pos.x + 26 + self.baro.x,
			cam.pos.y + 2 + self.baro.y,
			1
		)
		corneroffset += vec2(1, 1)
		line(
			corneroffset.x,
			corneroffset.y,
			cam.pos.x + 25 + self.baro.x,
			cam.pos.y + 1 + self.baro.y,
			8
		)
		if player.stamina > 0 then
			line(
				cam.pos.x + 1 + self.baro.x,
				flr(cam.pos.y + 1 + self.baro.y),
				cam.pos.x + mid(1, flr(player.stamina / 4), 25) + self.baro.x,
				cam.pos.y + 1 + self.baro.y,
				11
			)
		end
		-- grip icon
		if player.holding then
			spr(50, cam.pos.x + 55 + self.hando.x, cam.pos.y + self.hando.y)
		else
			spr(49, cam.pos.x + 55 + self.hando.x, cam.pos.y + self.hando.y)
		end
		if (player.has_chalk) spr(58, cam.pos.x + 55, cam.pos.y+55)
		if (player.finished) getsendy()
	end,
	shakehand = function(self)
		self.hando = vec2(0, 0)
		--Should check if there is already a coroutine running , and either delete it
		--or resume it. This prevents a crash in the event you spam the button too much.
		--Fix this post jam
		sfx(8, -2)
		sfx(8, -1, 0, 12)
		shakeh = cocreate(sinxshake)
		coresume(shakeh, self.hando, 2, 2, 10)
		add(coroutines, shakeh)
	end,
	shakebar = function(self)
		self.baro = vec2(0, 0)
		--See note above
		sfx(7, -2)
		sfx(7, -1, 0, 12)
		shakeb = cocreate(sinxshake)
		coresume(shakeb, self.baro, 2, 2, 10)
		add(coroutines, shakeb)
	end
})
add(classes, c_hud:new({}))

tombstone = vec2(-1, -1)
-- levels can be max 4 height due to our draw space
levels = {
	-- level 1
	{
		name = "v-easy",
		face_tile = vec2(0, 0),
		bg = 18,
		screens = {
			--width
			{
				--height
				tombstone,
				vec2(1, 0),
				vec2(0, 0)
			}
		}
	},
	-- level 2
	{
		name = "traverse",
		face_tile = vec2(1, 2),
		bg = 21,
		screens = {
			--width
			{
				--height
				vec2(0, 3),
				vec2(0, 2)
			},
			{
				vec2(2, 3),
				vec2(1, 3)
			},
			{
				vec2(2, 2),
				vec2(1, 2)
			}
		}
	},
	-- level 3
	{
		name = "chalk",
		face_tile = vec2(13, 0),
		bg = 20,
		screens = {
			-- width
			{
				-- height
				tombstone,
				vec2(13, 0)
			},
			{
				tombstone,
				vec2(15, 0)
			}
		}
	},
	-- level 4
	{
		name = "climbers",
		face_tile = vec2(12, 2),
		bg = 21,
		screens = {
			-- width
			{
				-- height
				tombstone,
				vec2(12, 1),
				vec2(12, 2)
			},
			{
				tombstone,
				vec2(13, 1),
				vec2(13, 2)
			}
		}
	},
	-- level 5
	{
		name = "cracks",
		face_tile = vec2(12, 3),
		bg = 18,
		screens = {
			-- width
			{
				-- height
				tombstone,
				vec2(12, 0),
				vec2(12, 3)
			},
			{
				tombstone,
				tombstone,
				vec2(13, 3)
			}
		}
	},
	-- level 6
	{
		name = "crimp n' co.",
		face_tile = vec2(4, 0),
		bg = 23,
		screens = {
			-- width
			{
				-- height
				tombstone,
				vec2(7, 0),
				vec2(5, 0),
				vec2(4, 0)
			},
			{
				tombstone,
				vec2(6, 0),
				vec2(3, 0),
				vec2(2, 0)
			}
		}
	},
	-- level 7
	{
		name = "roundabout",
		face_tile = vec2(8, 0),
		bg = 19,
		screens = {
			-- width
			{
				-- height
				tombstone,
				vec2(8, 0),
				vec2(9, 0),
				vec2(14, 0)
			},
			{
				tombstone,
				vec2(11, 0),
				vec2(10, 0),
				vec2(14, 0)
			}
		}
	},
	-- level 8
	{
		name = "get crackin'",
		face_tile = vec2(1, 1),
		bg = 18,
		screens = {
			-- width
			{
				-- height
				tombstone,
				vec2(6, 1),
				vec2(3, 1),
				vec2(1, 1)
			},
			{
				tombstone,
				vec2(5, 1),
				vec2(4, 1),
				vec2(2, 1)
			}
		}
	},
	-- level 9
	{
		name = "todo",
		face_tile = vec2(12, 3),
		bg = 18,
		screens = {
			-- width
			{
				-- height
				tombstone,
				vec2(12, 0),
				vec2(12, 3),
				vec2(12, 3)
			},
			{
				tombstone,
				tombstone,
				tombstone,
				vec2(13, 3)
			}
		}
	},
	-- level 10
	{
		name = "journey's end",
		face_tile = vec2(12, 3),
		bg = 18,
		screens = {
			-- width
			{
				-- height
				tombstone,
				vec2(12, 0),
				vec2(12, 3),
				vec2(12, 3)
			},
			{
				tombstone,
				tombstone,
				tombstone,
				vec2(13, 3)
			}
		}
	}
}
level = nil
draw_offset = 256

function load_level(level_number)
	reload_map()
	jukebox:startplayingnow(level_number%2+3, 3000, 11)
	level = levels[level_number]
	local level_width = #level.screens
	local level_height = #level.screens[1]
	for x = 0, level_width - 1 do
		for y = 0, level_height - 1 do
			local screen = level.screens[x+1][y+1]
			-- ignore screens set to tombstone vector vec2(-1, -1)
			if screen.x >= 0 and screen.y >= 0 then
				for sx = 0, 7 do
					for sy = 0, 7 do
						local mapped_pos = vec2((screen.x*8)+(sx), (screen.y*8)+(sy))
						local world_pos = vec2(x*64+sx*8, y*64+sy*8+draw_offset)
						local tile = mget(mapped_pos.x, mapped_pos.y)
						foreach(classes, function(c)
							load_obj(world_pos, mapped_pos, c, tile)
						end)
						mset(world_pos.x/8, world_pos.y/8, tile) -- divide by 8 for chunks
					end
				end
			end
		end
	end
end

function save_highscore(score)
	local prev = dget(levelselection)
	if prev ~= 0 then
		if score < prev then
			dset(levelselection, score)
		end
	else
		dset(levelselection, score)
	end
end

function clear_state()
	actors = {}
	particles = {}
	if player then -- workaround for referential sprites table
		player.sprites.default.number = 1
	end
	player = nil
	toprope = nil
end

function load_obj(w_pos, m_pos, class, tile)
	local sprite = class.sprites.default.number
	if sprite == tile then
		if class.name == "granola" then
			add(actors, class:new({ p = w_pos }))
			mset(m_pos.x, m_pos.y, 0)
		elseif class.name == "chalk" then
			add(actors, class:new({ p = w_pos }))
			mset(m_pos.x, m_pos.y, 0)
		elseif class.name == "chalkhold" then
			add(actors, class:new({ p = w_pos }))
			mset(m_pos.x, m_pos.y, 0)
		elseif class.name == "player" then
			player = class:new({ p = w_pos })
			mset(m_pos.x, m_pos.y, 0)
			cam.pos = vec2(w_pos.x, w_pos.y) -- copy world_pos to avoid reference issues
		elseif class.name == "goal" then
			add(actors, class:new({ p = w_pos }))
			mset(m_pos.x, m_pos.y, 0)
		end
	end
end

function draw_leaves()
	--draw the sides of the level
	for y = 0, #level.screens[1] - 1 do
		for i = 0, 7 do
			yo = y*64+i*8+draw_offset
			spr(72, #level.screens * 64 - 8, yo, 1, 1, false, rand_bool())
			spr(72, 0, yo, 1, 1, true, rand_bool())
		end
	end
end

function draw_level()
	clip(cam.x, cam.y, 64, 64)
	-- Draw the background leaves based on camera position
	for x = 0, 8, 1 do
		for y = 0, 8, 1 do
			local camo = vec2(cam.pos.x %8 + 8, cam.pos.y %8 + 8)
			srand((cam.pos.x - camo.x + x * 8) + cam.pos.y - camo.y + y * 8)
			spr(73, cam.pos.x - camo.x + x * 8 + 8, cam.pos.y - camo.y + y * 8 + 8, 1, 1, rand_bool(), rand_bool())
		end
	end

	--draw the elements in the level
	local level_width = #level.screens
	local level_height = #level.screens[1]
	for x = 0, level_width - 1 do
		for y = 0, level_height - 1 do
			local screen = level.screens[x+1][y+1]
			draw_bg(x, y, level.bg, true)
			-- ignore screens set to tombstone vector vec2(-1, -1)
			if screen.x >= 0 and screen.y >= 0 then
				map(screen.x*8, screen.y*8, x*64, y*64+draw_offset, 8, 8)
			end
		end
	end
end

-- is_level accounts for draw_offset and ground tiles below level height
function draw_bg(x, y, bg, is_level)
	srand(800)
	for sx = 0, 7 do
		for sy = 0, 7 do
			local world_pos = is_level and vec2(x*64 + sx*8, y*64 + sy*8 + draw_offset) or vec2(sx*8, sy*8)
			spr(bg, world_pos.x, world_pos.y, 1, 1, rand_bool(), rand_bool())
			if is_level then
				spr(31, world_pos.x, world_pos.y + #level.screens[1]*64, 1, 1, rand_bool(), rand_bool())
			end
		end
	end
end

function setup()
	poke(0x5f2c,3) -- enable 64 bit mode
	-- set lavender to the transparent color
	palt(0, false)
	palt(13, true)
end

-- reset the map from rom (if you make in-ram changes)
function reload_map()
	reload(0x2000, 0x2000, 0x1000)
	setup()
	-- clear the draw space
	for x = 0, 63 do
		for y = 32, 63 do
			mset(x, y, 0)
		end
	end
end

function _init()
	cartdata("hot_beans_yolo_solo")
	setup()
	jukebox = c_jukebox:new({})
	init_screen()
end

function update_game()
	player.on_chalkhold = false
	local hold = player:hold_collide()
	-- reset player holds to check again on next loop
	player.on_jug, player.on_crack, player.on_crimp = false, false, false
	if hold == "jug" then
		player.on_jug = true
	elseif hold == "crack" then
		player.on_crack = true
	elseif hold == "crimp" then
		player.on_crimp = true
	end
	foreach(actors, function(a)
		a:update()
		player:collide(a)
	end)
	if (not player.dead) then
		player:move()
	else
		if rspwn == nil or costatus(rspwn) == "dead" then
			rspwn = cocreate(respawn)
			add(coroutines, rspwn)
		end
	end
	resumecoroutines()
end

function draw_game()
	cls()
	draw_level(levelselection)
	foreach(actors, function(a) a:draw() end)
	toprope:drawrope()
	player:draw()
	draw_leaves()
	drawparticles()
	cam:update(player.p)
	hud:draw()
	--getsendy()
	drawtransition()
	-- print("cpu "..stat(1), player.p.x-20, player.p.y - 5, 7)
end

function init_game()
	_update = update_game
	_draw = draw_game

	load_level(levelselection)

	player.statemachine.parent = player
	player.finished = false
	--transition into screen
	if (tran == nil or costatus(tran) == "dead") and not level_loaded then
		tran = cocreate(transition)
		add(coroutines, tran)
	end
	if ((not level_loaded and not player.dead) or resetbuttonpressed) start_time = time()
	level_loaded = true
	--player.movable = true
	hud = c_hud:new({})
	toprope = rope:create()
	-- this if statement prevents a bug when resuming after returning to menu
	if parts == nil then
		parts = cocreate(solveparticles)
		add(coroutines, parts)
	end
	if flock == nil then
		flock = cocreate(spawnflock)
		add(coroutines, flock)
	end
	menuitem(2, "back to menu", init_menu)
	menuitem(1, "reload level", timereset)
	--jukebox:startplayingnow(3, 2000, 11)
end

function timereset()
	resetbuttonpressed, player.dead = true, false
	respawn()
end

function respawn()
	if not player.finished then
		--player.v = vec2(0, 0)
		local respawntimer = time() + 1
		while time() < respawntimer and player.dead do
			yield()
		end
		--if (player and not player.dead) start_time = time()
		clear_state()
		init_game()
		player.dead = false
		for i = 1, 10, 1 do
			local o = player.p + vec2(sin(10/i) * 10 - 4, cos(10/i) * 10 - 4)
			local p = c_particle:new({p = player.p + vec2(sin(10/i) * 15, cos(10/i) * 15), v = (player.p-o)*5, life = 10, c = 14})
			add(particles, p)
		end
		sfx(12, 3)
		player.movable = true
		player.v = vec2(0, 0)
		resetbuttonpressed = false
	end
end

c_goal = c_object:new({
	name = "goal",
	sprites = {
		default = {
			number = 60,
			hitbox = {o = vec2(0, 0), w = 8, h = 8}
		}
	},
	anims = {
		wave = c_anim:new({
			frames = {60, 61, 62, 63},
			fr = 5,
			fc = 4,
			playing = true
		})
	},
	next_level = function(self)
		local end_time = time()
		formatted_time = format_time(end_time - start_time)
		save_highscore(end_time - start_time)

		local reloadtime = end_time + 5
		jukebox.playing = true
		jukebox:startplayingnow(5)
		player.movable = false
		while time() < reloadtime do
			yield()
		end
		if (music_on == "off") jukebox:stopplaying()

		if levelselection == #levels+1 then
			-- todo: go to credits/main menu
			printh("done")
		end
		levelselection += 1
		for i = 64, 1, -5 do
			transitionbox = {vec2(i, 0), vec2(64, 64)}
			yield()
		end
		transitionbox = nil
		level_loaded = false
		clear_state()
		init_game()
	end,
	draw = function(self)
		local frame = self.anims.wave:loopforward()
		--frame = self.anims.wave.frames[frame]
		spr(frame, self.p.x, self.p.y)
	end
})
add(classes, c_goal:new({}))

function spawnflock()
	while true do
		srand(time())
		-- Every ten seconds, there's a 10 percent chance of spawning a flock
		if time() % 10 == 1 and flr(rnd(10)) == 1 then
			for i=-3, 3 do
				add(particles, s_particle:new({fo = flr(rnd(4)),
				sprites = {45, 46, 47},
				life = 500,
				p = vec2(#level.screens*64 + 64 +(rnd(5)-10),
					#level.screens[1] * 110+(rnd(5)-10)) + vec2(abs(i) * 6, i * 6),
				v = vec2(-50, 0)}))
			end
		end
		yield()
	end
end

-- Transitioning into start of level
function transition()
	for i = 64, 1, -5 do
		transitionbox = {vec2(0, 0), vec2(i, 64)}
		yield()
	end
	transitionbox = nil
	player.movable = true
end

-- Drawing the actual transition
function drawtransition()
	if transitionbox != nil then
		rectfill(cam.pos.x + transitionbox[1].x,
		cam.pos.y + transitionbox[1].y,
		cam.pos.x + transitionbox[2].x,
		cam.pos.y + transitionbox[2].y, 0)
	end
end

function getsendy()
	local cx = cam.pos.x
	local cy = cam.pos.y
	local sinvals = {}
	for i = 1, #"let's get sendy" + 1, 1 do
		add(sinvals, flr(sin(time()-i/8)*-1.5))
		circfill(cx+i*4-2, cy+12+sinvals[i], 5, 7)
	end
	for i = 1, #"let's get sendy", 1	do
		--local sinval = flr(sin(time()-i/8)*-1.5)
		?sub("let's get sendy!",i,i), cx+i*4-2,cy+10+sinvals[i],1
	end
	if (formatted_time != nil) then
		rectfill(cx + (31-#formatted_time*2), cy + 23, cx + (33+#formatted_time*2), cy + 31, 7)
		?formatted_time, cx + (33-#formatted_time*2), cy + 25, 1
	end
end
