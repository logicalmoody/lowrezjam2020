function sinxshake(pos, a, s, t)
	local p = pos.x
	for i = 1, t do
		pos.x = p + sin(i*s/10)*(a/i*a)
		yield()
	end
	pos.x = p
end

function clearcoroutines()
	for c in all(coroutines) do
		del(coroutines, c)
		c = nil
	end
	parts, tran, flock, rspwn, nextlvl = nil, nil, nil, nil, nil
end

function resumecoroutines()
	for c in all(coroutines) do
	if c and costatus(c) != 'dead' then
		assert(coresume(c))
    else
		del(coroutines, c)
    end
  end
end
