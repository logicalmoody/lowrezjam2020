i = 1
randomx = false
randomy = false
function testtiles()
  local tiles = {17, 18, 19, 20, 21, 22, 23, 24, 25, 26}
  srand(800)
  //draw the background
  if btnp(1) then
    i += 1
  elseif btnp(0) then
    i -= 1
  end
  if btnp(5) and randomx == false then
    randomx = true
  elseif btnp(5) then
    randomx = false
  end
  if btnp(4) and randomy == false then
    randomy = true
  elseif btnp(4) then
    randomy = false
  end
  for j=0, 64, 1 do
    flipx = false
    flipy = false
    if randomx == true then
      if (flr(rnd(2)) == 1) flipx = true
    end
    if randomy == true then
      if (flr(rnd(2)) == 1) flipy = true
    end
    spr(tiles[i], j%8*8, flr(j/8)*8, 1, 1, flipx, flipy)
  end
  //draw the character
  spr(1, 32, 32)
end