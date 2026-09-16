local V=...
local GX=V.GXTexture
local H={cameraRevision=2}
local floor,abs,sqrt=math.floor,math.abs,math.sqrt
local RETAIL_SCALE_MIN=0.0010000000474974513 -- f32 bits 0x3A83126F
local function u16(s,p)local a,b=s:byte(p,p+1);if not b then return nil end;return a*256+b end
local function s16(s,p)local v=u16(s,p);if not v then return nil end;return v>=32768 and v-65536 or v end
local function u32(s,p)local a,b,c,d=s:byte(p,p+3);if not d then return nil end;return ((a*256+b)*256+c)*256+d end
local function f32(s,p)
  local v=u32(s,p);if not v then return nil end
  local sign=v>=2147483648 and -1 or 1;if sign<0 then v=v-2147483648 end
  local e=floor(v/8388608);local m=v%8388608
  if e==255 then return 0/0 end
  if e==0 then return sign*(m/8388608)*2^-126 end
  return sign*(1+m/8388608)*2^(e-127)
end
local function finite(x)return type(x)=="number" and x==x and abs(x)<1e12 end
local function cstr(s,p)local e=s:find("\0",p,true) or (#s+1);return s:sub(p,e-1) end
local function ident()return {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1} end
local function mul(a,b)
  local o={};for r=0,3 do for c=0,3 do local q=0;for k=0,3 do q=q+a[r*4+k+1]*b[k*4+c+1] end;o[r*4+c+1]=q end end;return o
end
local function localM(rx,ry,rz,sx,sy,sz,tx,ty,tz,parentScale)
  local cx,snx=math.cos(rx),math.sin(rx);local cy,sny=math.cos(ry),math.sin(ry);local cz,snz=math.cos(rz),math.sin(rz)
  local matrix={
    cz*cy*sx,(cz*sny*snx-snz*cx)*sy,(cz*sny*cx+snz*snx)*sz,tx,
    snz*cy*sx,(snz*sny*snx+cz*cx)*sy,(snz*sny*cx-cz*snx)*sz,ty,
    -sny*sx,cy*snx*sy,cy*cx*sz,tz,
    0,0,0,1,
  }
  if parentScale then
    for row=1,3 do
      local divisor=parentScale[row]
      if abs(divisor)<1e-8 then divisor=divisor<0 and -1e-8 or 1e-8 end
      for column=1,3 do
        local index=(row-1)*4+column
        matrix[index]=matrix[index]*parentScale[column]/divisor
      end
    end
  end
  return matrix
end
local function inheritedScale(parentScale,sx,sy,sz,classical)
  if classical then return parentScale end
  return {sx*(parentScale and parentScale[1] or 1),sy*(parentScale and parentScale[2] or 1),sz*(parentScale and parentScale[3] or 1)}
end
-- Affine inverse (3x3 block via cofactor/adjugate, translation solved from it).
-- Needed to build a per-bone skinning matrix (world * invert(bindWorld)) for
-- vertices genuinely blended across more than one joint -- see the comment on
-- envelopeWorld below for why a single-bone envelope does not need this.
local function invertAffine(m)
  local a,b,c,tx=m[1],m[2],m[3],m[4]
  local d,e,f,ty=m[5],m[6],m[7],m[8]
  local g,h,i,tz=m[9],m[10],m[11],m[12]
  local det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
  if abs(det)<1e-12 then return ident() end
  local id=1/det
  local A,B,C=(e*i-f*h)*id,(c*h-b*i)*id,(b*f-c*e)*id
  local D,E,F=(f*g-d*i)*id,(a*i-c*g)*id,(c*d-a*f)*id
  local G,H,I=(d*h-e*g)*id,(b*g-a*h)*id,(a*e-b*d)*id
  return {A,B,C,-(A*tx+B*ty+C*tz), D,E,F,-(D*tx+E*ty+F*tz), G,H,I,-(G*tx+H*ty+I*tz), 0,0,0,1}
end
local function point(m,x,y,z)return m[1]*x+m[2]*y+m[3]*z+m[4],m[5]*x+m[6]*y+m[7]*z+m[8],m[9]*x+m[10]*y+m[11]*z+m[12] end
-- A world matrix's scale along each local axis is the length of that axis's
-- column; an isotropic-equivalent single number (their geometric mean) is
-- near zero exactly when at least one axis has collapsed, even if the other
-- two look fine. Used to spot a joint whose world transform is degenerate
-- (collapses whatever mesh hangs off it to a point) without needing to know
-- anything about skinning, hidden flags, or the pose sampler -- see the
-- comment on noteJointWorld in extractRoot for why this is tracked per-joint
-- rather than per texture-merged render group.
local function worldScaleTrans(m)
  local sx=sqrt(m[1]*m[1]+m[5]*m[5]+m[9]*m[9])
  local sy=sqrt(m[2]*m[2]+m[6]*m[6]+m[10]*m[10])
  local sz=sqrt(m[3]*m[3]+m[7]*m[7]+m[11]*m[11])
  local scale=(sx*sy*sz)^(1/3)
  local trans=sqrt(m[4]*m[4]+m[8]*m[8]+m[12]*m[12])
  return scale,trans,sx,sy,sz
end
local function normal(m,x,y,z)local a,b,c=m[1]*x+m[2]*y+m[3]*z,m[5]*x+m[6]*y+m[7]*z,m[9]*x+m[10]*y+m[11]*z;local l=sqrt(a*a+b*b+c*c);if l<1e-9 then return 0,1,0 end;return a/l,b/l,c/l end
local function hasFlag(v,bit) return (tonumber(v) or 0)%(bit*2)>=bit end
local function hsdMatrix4x3(a,p)
  if not p or p+0x30>a.base+a.fileSize then return nil end
  local b=a.blob;local m={}
  for i=0,11 do
    local v=f32(b,p+i*4+1);if not finite(v) then return nil end;m[i+1]=v
  end
  return {m[1],m[2],m[3],m[4], m[5],m[6],m[7],m[8], m[9],m[10],m[11],m[12], 0,0,0,1}
end
local function align32(n)return n+((0x20-(n%0x20))%0x20) end

-- HSD animation FOBJ payloads are little-endian even though the surrounding
-- DAT structs are big-endian. Keep the readers separate so native trainer
-- animation sampling cannot accidentally reuse the geometry readers.
local function le16(s,p)local a,b=s:byte(p,p+1);if not b then return nil end;return a+b*256 end
local function les16(s,p)local v=le16(s,p);if not v then return nil end;return v>=32768 and v-65536 or v end
local function lef32(s,p)
  local a,b,c,d=s:byte(p,p+3);if not d then return nil end
  local v=a+b*256+c*65536+d*16777216
  local sign=v>=2147483648 and -1 or 1;if sign<0 then v=v-2147483648 end
  local e=floor(v/8388608);local m=v%8388608
  if e==255 then return 0/0 end
  if e==0 then return sign*(m/8388608)*2^-126 end
  return sign*(1+m/8388608)*2^(e-127)
end
local function packed(s,p,limit)
  local result,shift=0,0
  for _=1,5 do
    if p>(limit or #s) then return nil,p end
    local b=s:byte(p);p=p+1;if not b then return nil,p end
    result=result+(b%128)*(2^shift)
    if b<128 then return result,p end
    shift=shift+7
  end
  return nil,p
end
local function animScalar(blob,p,fmt,scale,limit)
  scale=scale or 1
  if fmt==0 then local v=lef32(blob,p);return v and v/scale or nil,p+4 end
  if fmt==0x20 then local v=les16(blob,p);return v and v/scale or nil,p+2 end
  if fmt==0x40 then local v=le16(blob,p);return v and v/scale or nil,p+2 end
  local b=blob:byte(p);if not b then return nil,p+1 end
  if fmt==0x60 and b>=128 then b=b-256 end
  return b/scale,p+1
end
local function decodeFobj(a,fd)
  local cached=a._fobjCache and a._fobjCache[fd]
  if cached then return cached.track,cached.keys end
  local blob=a.blob;local len=u32(blob,fd+0x04+1) or 0;local start=f32(blob,fd+0x08+1) or 0
  local track=blob:byte(fd+0x0C+1) or 0;local vf=blob:byte(fd+0x0D+1) or 0;local tf=blob:byte(fd+0x0E+1) or 0
  local data=a:ptr(fd+0x10);if not data or len<=0 or len>16*1024*1024 then return track,{} end
  local p,limit=data+1,math.min(data+len,#blob);local clock=0;local keys={}
  local vfmt=vf-(vf%0x20);local tfmt=tf-(tf%0x20);local vscale=2^(vf%0x20);local tscale=2^(tf%0x20)
  while p<=limit do
    local code;code,p=packed(blob,p,limit);if not code then break end
    local op=code%16;local count=floor(code/16)+1;if op==0 or op>6 then break end
    for _=1,count do
      if p>limit+1 then break end
      local value,tan,time=0,0,0
      if op==1 or op==2 or op==3 then value,p=animScalar(blob,p,vfmt,vscale,limit);time,p=packed(blob,p,limit)
      elseif op==4 then value,p=animScalar(blob,p,vfmt,vscale,limit);tan,p=animScalar(blob,p,tfmt,tscale,limit);time,p=packed(blob,p,limit)
      elseif op==5 then tan,p=animScalar(blob,p,tfmt,tscale,limit)
      elseif op==6 then value,p=animScalar(blob,p,vfmt,vscale,limit);time,p=packed(blob,p,limit) end
      if value==nil or tan==nil then break end
      keys[#keys+1]={frame=clock,value=value,tan=tan or 0,op=op};clock=clock+(time or 0)
    end
  end
  if start~=0 then
    -- startframe is a SEEK into an existing FOBJ stream, not a filter.
    -- Keep keys before the requested origin: they establish the value and
    -- Hermite tangent on the left of frame zero. Removing them resets scale
    -- tracks to zero (Blastoise/Diglett) and loses Articuno's neck rotation.
    for _,k in ipairs(keys) do k.frame=k.frame-start end
  end
  a._fobjCache=a._fobjCache or {}
  a._fobjCache[fd]={track=track,keys=keys}
  return track,keys
end
local function fobjValue(keys,frame)
  if not keys or #keys==0 then return nil end
  -- A delayed stream has not written this channel yet; retain its JOBJ
  -- transform. A pre-rolled stream, in contrast, still has its earlier keys.
  if frame<keys[1].frame then return nil end
  if frame>=keys[#keys].frame then
    for i=#keys,1,-1 do if keys[i].op~=5 then return keys[i].value end end
    return nil
  end
  local p0,p1,d0,d1,t0,t1=0,0,0,0,0,0;local opPrev,op=1,1
  for _,k in ipairs(keys) do
    opPrev=op;op=k.op
    if op==1 or op==2 then p0=p1;p1=k.value;if opPrev~=5 then d0=d1;d1=0 end;t0=t1;t1=k.frame
    elseif op==3 then p0=p1;d0=d1;p1=k.value;d1=0;t0=t1;t1=k.frame
    elseif op==4 then p0=p1;p1=k.value;d0=d1;d1=k.tan;t0=t1;t1=k.frame
    elseif op==5 then d0=d1;d1=k.tan
    elseif op==6 then p0=p1;p1=k.value;t0=t1;t1=k.frame end
    if t1>frame and op~=5 then break end
    opPrev=op
  end
  if frame<=t0 then return p0 end;if frame>=t1 then return p1 end
  if t0==t1 or opPrev==1 or opPrev==6 then return p0 end
  local time=frame-t0;local span=t1-t0
  if opPrev==2 then return p0+(p1-p0)*(time/span) end
  if opPrev==3 or opPrev==4 or opPrev==5 then
    local inv=1/span;local f1=time*time;local f2=inv*inv*f1*time;local f3=3*f1*inv*inv;local f4=f2-f1*inv;local f2b=2*f2*inv
    return d1*f4+d0*(time+(f4-f1*inv))+p0*(1+(f2b-f3))+p1*(-f2b+f3)
  end
  return p0
end
local function findModelSet(a,root)
  local scene=a:publicSymbol("scene_data");local sets=scene and a:ptr(scene) or nil;if not sets then return nil end
  for i=0,127 do local ms=a:ptr(sets+i*4);if not ms then break end;if a:ptr(ms)==root then return ms end end
end
local function nativeAnimations(a,root)
  local ms=findModelSet(a,root);local arr=ms and a:ptr(ms+0x04) or nil;local out={};if not arr then return out end
  for i=0,63 do local r=a:ptr(arr+i*4);if not r then break end;out[#out+1]=r end
  return out
end
-- GC6E01 GSmodelResource is {joint, anims, texAnims, shapeAnims}.  Despite the
-- historical "texAnim" name, the +0x08 array contains HSD_MatAnimJoint roots:
-- GSmodelSetTexAnimIndex passes one directly to fn_801A2B5C as matanimjoint.
-- People animation setup selects this bank with the same zero-based index/frame
-- as the skeletal bank, so preserving the parallel list is source-defined rather
-- than an inferred blink/material pairing.
local function nativeMaterialAnimations(a,root)
  local ms=findModelSet(a,root);local arr=ms and a:ptr(ms+0x08) or nil;local out={};if not arr then return out end
  for i=0,63 do local r=a:ptr(arr+i*4);if not r then break end;out[#out+1]=r end
  return out
end
local function nativeClipInfo(a,root,clipIndex)
  local clips=nativeAnimations(a,root)
  local ci=math.max(0,math.floor(tonumber(clipIndex) or 0))
  local ar=clips[ci+1]
  if not ar then return nil,#clips end
  local maxEnd=0
  local aobjs=0
  local seen={}
  local function walk(aj,depth)
    if not aj or seen[aj] or depth>256 then return end
    seen[aj]=true
    local aobj=a:ptr(aj+0x08)
    if aobj then
      aobjs=aobjs+1
      local ef=f32(a.blob,aobj+0x04+1)
      if finite(ef) and ef>=0 and ef<100000 and ef>maxEnd then maxEnd=ef end
    end
    walk(a:ptr(aj),depth+1)
    walk(a:ptr(aj+0x04),depth+1)
  end
  walk(ar,0)
  return {clip=ci,endFrame=maxEnd,frameCount=math.max(1,math.floor(maxEnd+.5)+1),aobjCount=aobjs,clipCount=#clips},#clips
end

local function nativePose(a,root,clipIndex,frame)
  -- nativePose clip ids are zero-based at the extractor boundary. Lua tables are
  -- one-based, so clip 0 addresses the first HSD animation entry. Its role
  -- is asset-specific: some trainer DATs use a bind pose, while many PKX
  -- Pokemon use a real animated idle. Callers resolve roles from metadata.
  local clips=nativeAnimations(a,root)
  local ci=math.max(0,math.floor(tonumber(clipIndex) or 0))
  local ar=clips[ci+1];if not ar then return nil,#clips end
  local pose={};local seenJ,seenA={},{ }
  local function pair(j,aj,depth)
    if not j or not aj or seenJ[j] or seenA[aj] or depth>256 then return end
    seenJ[j]=true;seenA[aj]=true
    local b=a.blob;local s={
      f32(b,j+0x14+1) or 0,f32(b,j+0x18+1) or 0,f32(b,j+0x1C+1) or 0,
      f32(b,j+0x20+1) or 1,f32(b,j+0x24+1) or 1,f32(b,j+0x28+1) or 1,
      f32(b,j+0x2C+1) or 0,f32(b,j+0x30+1) or 0,f32(b,j+0x34+1) or 0}
    local aobj=a:ptr(aj+0x08);local fd=aobj and a:ptr(aobj+0x08) or nil;local guard=0
    while fd and guard<64 do guard=guard+1;local track,keys=decodeFobj(a,fd);local v=fobjValue(keys,frame or 0)
      if v~=nil then if track>=1 and track<=3 then s[track]=v elseif track>=5 and track<=7 then s[track+2]=v elseif track>=8 and track<=10 then s[track-4]=v end end
      fd=a:ptr(fd)
    end
    s.classicalScale=(u32(b,aj+0x10+1) or 0)%2==1
    pose[j]=s
    pair(a:ptr(j+0x08),a:ptr(aj),depth+1);pair(a:ptr(j+0x0C),a:ptr(aj+0x04),depth+1)
  end
  pair(root,ar,0);return pose,#clips
end

-- Exact-bound animation audit layered over nativePose. The ordinary pose path
-- intentionally ignores channels it does not need for render morphs; a GSmodel
-- bound cannot do that because PATH/NODE/BRANCH/matrix channels and AObj obj_id
-- can change the frame-0 transform or visibility before GSmodelParse runs.
local function nativeRetailBoundPose(a,root,clipIndex)
  local pose,clipCount=nativePose(a,root,clipIndex,0)
  if not pose then return nil,clipCount end
  local clips=nativeAnimations(a,root)
  local ci=math.max(0,math.floor(tonumber(clipIndex) or 0))
  local ar=clips[ci+1]
  if not ar then return nil,#clips end
  local seenJ,seenA={},{}
  local blocker=nil
  local function pair(j,aj,depth)
    if blocker or not j or not aj or seenJ[j] or seenA[aj] or depth>256 then return end
    seenJ[j]=true;seenA[aj]=true
    local aobj=a:ptr(aj+0x08)
    if aobj then
      local aflags=u32(a.blob,aobj+1) or 0
      if hasFlag(aflags,0x10000000) then blocker="retail-bound frame-0 AObj NO_UPDATE unsupported";return end
      local objId=u32(a.blob,aobj+0x0C+1) or 0
      -- obj_id is relocation-bearing HSD object identity. Raw offset zero can
      -- therefore still resolve to data-section object zero when that field is
      -- listed in the archive relocation table.
      if objId~=0 or a:ptr(aobj+0x0C) then blocker="retail-bound frame-0 AObj obj_id transform unsupported";return end
      local fd=a:ptr(aobj+0x08);local guard=0
      while fd and guard<64 do
        guard=guard+1
        local track,keys=decodeFobj(a,fd)
        if not ((track>=1 and track<=3) or (track>=5 and track<=10)) then
          blocker=("retail-bound frame-0 JObj animation track %d unsupported"):format(track or -1);return
        end
        local value=fobjValue(keys,0)
        if value~=nil and track>=8 and track<=10 and abs(value)<RETAIL_SCALE_MIN then
          -- fn_801A20C8 clamps any animated |scale| below 0x3A83126F to +0.001f.
          local s=pose[j]
          if not s then blocker="retail-bound frame-0 animated JObj pose unavailable";return end
          s[track-4]=RETAIL_SCALE_MIN
        end
        fd=a:ptr(fd)
      end
      if fd then blocker="retail-bound frame-0 FObj chain exceeds audit budget";return end
    end
    pair(a:ptr(j+0x08),a:ptr(aj),depth+1)
    pair(a:ptr(j+0x0C),a:ptr(aj+0x04),depth+1)
  end
  pair(root,ar,0)
  if blocker then return nil,clipCount,blocker end
  return pose,clipCount
end

local function archiveAt(blob,base)
  local fileSize,dataSize,relocs,pubs,ext=u32(blob,base+1),u32(blob,base+5),u32(blob,base+9),u32(blob,base+13),u32(blob,base+17)
  if not (fileSize and dataSize and relocs and pubs and ext) then return nil end
  if fileSize<0x20 or base+fileSize>#blob or dataSize>=fileSize or relocs>200000 or pubs>8192 or ext>8192 then return nil end
  local data=base+0x20;local reloc=data+dataSize;local public=reloc+relocs*4;local external=public+pubs*8;local strings=external+ext*8
  if strings>base+fileSize then return nil end
  local a={blob=blob,base=base,fileSize=fileSize,dataSize=dataSize,data=data,reloc=reloc,relocCount=relocs,public=public,publicCount=pubs,external=external,externalCount=ext,strings=strings}
  function a:ptr(field)
    local raw=u32(blob,field+1);if not raw then return nil end
    if raw==0 then
      -- Locate() relocates EVERY listed field, including data offset zero.
      -- An unlisted zero is a null pointer. Build this set only when needed.
      if not self._relocatedFields then
        local fields={}
        for i=0,self.relocCount-1 do
          local offset=u32(blob,self.reloc+i*4+1)
          if offset and offset>=0 and offset+4<=self.dataSize then fields[self.data+offset]=true end
        end
        self._relocatedFields=fields
      end
      if not self._relocatedFields[field] then return nil end
    end
    local p=self.data+raw;if p<self.data or p>=self.data+self.dataSize then return nil end;return p
  end
  function a:publicSymbol(name)
    for i=0,self.publicCount-1 do local p=self.public+i*8;local ro,no=u32(blob,p+1),u32(blob,p+5);if ro and no then local npos=self.strings+no;if npos<self.base+self.fileSize then local n=cstr(blob,npos+1);if n==name then return self.data+ro end end end end
  end
  function a:publicSymbols()
    local out={}
    for i=0,self.publicCount-1 do
      local p=self.public+i*8;local ro,no=u32(blob,p+1),u32(blob,p+5)
      if ro and no then
        local npos=self.strings+no
        if npos<self.base+self.fileSize then out[#out+1]={name=cstr(blob,npos+1),ptr=self.data+ro} end
      end
    end
    return out
  end
  return a
end

local function knownArchiveOffsets(blob)
  local out,seen={},{}
  local function add(v)if type(v)=="number" and v>=0 and v<=#blob-0x20 and not seen[v] then seen[v]=true;out[#out+1]=v end end
  add(0);add(0x20);add(0x40)
  -- Pokemon Colosseum PKX: fixed 0x40-byte wrapper followed by the DAT.
  -- Pokemon XD PKX: dynamic animation/GPT1 wrapper. Supporting both here is
  -- cheap and also makes diagnostics useful if a source archive mixes formats.
  if #blob>=0x84 then
    local first=u32(blob,1);local at40=u32(blob,0x41)
    if first and at40 and first~=at40 then
      local gpt=u32(blob,9) or 0;local anim=u32(blob,0x11) or 17
      if anim>0 and anim<128 then add(align32(0x84+anim*0xD0)+align32(gpt)) end
      add(0xE60+align32(gpt))
    elseif first and at40 and first==at40 then add(0x40) end
  end
  return out,seen
end

function H.findArchives(blob)
  local out={};local offsets,seen=knownArchiveOffsets(blob)
  local function add(base)
    if not seen["a"..base] then
      local a=archiveAt(blob,base)
      if a then seen["a"..base]=true;out[#out+1]=a end
    end
  end
  for _,base in ipairs(offsets) do add(base) end
  -- DAT/PKX trainer members overwhelmingly resolve at one of the canonical
  -- wrapper offsets above. Do not brute-force another 16K candidate headers
  -- when a canonical archive already validated; that cost multiplied by the
  -- 100+ people_archive members was a major first-run stall.
  if #out==0 then
    -- Some FSYS members carry a proprietary preamble. Only then search a
    -- bounded 64 KiB prefix; archiveAt performs strict structural validation.
    local max=math.min(0x10000,#blob-0x20)
    for base=0,max,4 do add(base) end
  end
  table.sort(out,function(a,b)return a.base<b.base end)
  return out
end

-- Deep archive discovery for bounded one-time extraction jobs such as retail
-- capture .fdat members. Normal trainer/arena paths intentionally keep the
-- fast 64 KiB search in findArchives(); this variant may scan the full member.
function H.findArchivesDeep(blob,maxBytes)
  if type(blob)~="string" then return {} end
  local out,seen={},{}
  local limit=math.min(tonumber(maxBytes) or #blob,#blob)-0x20
  if limit<0 then return out end
  for base=0,limit,4 do
    local a=archiveAt(blob,base)
    if a and not seen[base] then seen[base]=true;out[#out+1]=a end
  end
  table.sort(out,function(a,b)return a.base<b.base end)
  return out
end

function H.findArchive(blob)
  local archives=H.findArchives(blob)
  for _,a in ipairs(archives) do if a:publicSymbol("scene_data") then return a end end
  return archives[1]
end

local function readComp(blob,p,ctype,frac)
  frac=frac or 0
  if ctype==4 then return f32(blob,p),4 end
  if ctype==0 then return (blob:byte(p) or 0)/(2^frac),1 end
  if ctype==1 then local v=blob:byte(p) or 0;if v>=128 then v=v-256 end;return v/(2^frac),1 end
  if ctype==2 then return (u16(blob,p) or 0)/(2^frac),2 end
  if ctype==3 then return (s16(blob,p) or 0)/(2^frac),2 end
  return 0,1
end
local function componentCount(attr,cnt,directMode)
  if attr==9 then return cnt==0 and 2 or 3 end
  -- GX normal component-count values are not simple scalar counts:
  --   XYZ  (0): one 3-component normal
  --   NBT  (1): one index/direct record containing N+B+T (9 scalars)
  --   NBT3 (2): THREE indices (one each for N/B/T), each selecting a
  --             normal-sized 3-scalar record.  Direct NBT3 still carries
  --             all three vectors inline.
  -- Treating NBT3 as one 9-scalar indexed record shifts the display-list
  -- cursor by 2 missing indices and corrupts every following attribute.
  if attr==10 then
    if cnt==0 then return 3 end
    if cnt==1 then return 9 end
    if cnt==2 then return directMode and 9 or 3 end
    return 3
  end
  -- Some HSD serializers expose the tangent basis as GX_VA_NBT (25).
  if attr==25 then return (cnt==2 and not directMode) and 3 or 9 end
  if attr>=13 and attr<=20 then return cnt==0 and 1 or 2 end
  if attr==11 or attr==12 then return 4 end
  return 1
end
local function colorDirectBytes(ctype)
  -- GX color component types are a different enum from numeric GXCompType.
  -- RGB565/RGBA4=2, RGB8/RGBA6=3, RGBX8/RGBA8=4 bytes.
  if ctype==0 or ctype==3 then return 2 end
  if ctype==1 or ctype==4 then return 3 end
  if ctype==2 or ctype==5 then return 4 end
  return 4
end
-- Optional arena-fidelity path. GX colors use a packed enum, NOT the
-- numeric position/normal component enum. Leave default actor/MoveFX decoding
-- unchanged unless the caller explicitly requests preserveVertexColors.
local function packedVertexColor(blob,p,ctype)
  local width=colorDirectBytes(ctype)
  if ctype<0 or ctype>5 or p<1 or p+width-1>#blob then return nil,p end
  local b1,b2,b3,b4=blob:byte(p,p+width-1)
  local r,g,b,a
  if ctype==0 then
    local n=b1*256+b2
    local r5=floor(n/2048);local g6=floor(n/32)%64;local b5=n%32
    r=r5*8+floor(r5/4);g=g6*4+floor(g6/16);b=b5*8+floor(b5/4);a=255
  elseif ctype==1 or ctype==2 then r,g,b,a=b1,b2,b3,255
  elseif ctype==3 then
    r=floor(b1/16)*17;g=(b1%16)*17;b=floor(b2/16)*17;a=(b2%16)*17
  elseif ctype==4 then
    local n=b1*65536+b2*256+b3
    local r6=floor(n/262144)%64;local g6=floor(n/4096)%64
    local b6=floor(n/64)%64;local a6=n%64
    r=r6*4+floor(r6/16);g=g6*4+floor(g6/16)
    b=b6*4+floor(b6/16);a=a6*4+floor(a6/16)
  else r,g,b,a=b1,b2,b3,b4 end
  return {r/255,g/255,b/255,a/255},p+width
end
local function parseDescs(a,p)
  local out={};local blob=a.blob
  for _=0,31 do
    if not p or p+0x17>=a.base+a.fileSize then break end
    local attr=u32(blob,p+1);if not attr or attr==255 then break end
    local typ,cnt,ctype=u32(blob,p+5),u32(blob,p+9),u32(blob,p+13)
    local scale=blob:byte(p+0x10+1) or 0;local stride=u16(blob,p+0x12+1) or 0
    -- HSD_VtxDescList.base_ptr is a RAW data-section offset, not a nullable
    -- relocated object pointer. Offset 0 is therefore valid and means the
    -- attribute buffer begins at byte 0 of the DAT data section. Trainer
    -- meshes in Colosseum commonly use base_ptr=0 for positions. Passing this
    -- field through a:ptr() incorrectly converted that valid buffer into nil,
    -- leaving every trainer POBJ with zero decodable position vertices.
    local rawBase=u32(blob,p+0x14+1)
    local arr=(rawBase and rawBase<a.dataSize) and (a.data+rawBase) or nil
    out[#out+1]={attr=attr,type=typ,count=cnt,ctype=ctype,frac=scale,stride=stride,array=arr}
    p=p+0x18
  end
  return out
end
local function indexed(desc,idx,blob,preserveColors)
  if preserveColors and (desc.attr==11 or desc.attr==12) then
    if not desc.array then return nil end
    local stride=desc.stride>0 and desc.stride or colorDirectBytes(desc.ctype)
    return packedVertexColor(blob,desc.array+idx*stride+1,desc.ctype)
  end
  if not desc.array then return nil end
  local n=componentCount(desc.attr,desc.count,false);local sz=(desc.ctype==4 and 4) or ((desc.ctype==2 or desc.ctype==3) and 2 or 1);local stride=desc.stride>0 and desc.stride or n*sz
  local p=desc.array+idx*stride+1;local v={};for i=1,n do local q,d=readComp(blob,p,desc.ctype,desc.frac);v[i]=q;p=p+d end;return v
end
local function direct(desc,blob,p)
  local n=componentCount(desc.attr,desc.count,true);local v={};for i=1,n do local q,d=readComp(blob,p,desc.ctype,desc.frac);v[i]=q;p=p+d end;return v,p
end
local function readVertex(descs,blob,p,posMap,preserveColors)
  local out={}
  for _,d in ipairs(descs) do
    if d.attr<=8 then
      -- Matrix indices are normally DIRECT/INDEX8 (one byte), but honor
      -- INDEX16 if a source explicitly declares it so the stream stays aligned.
      local idx
      if d.type==1 or d.type==2 then idx=blob:byte(p) or 0;p=p+1
      elseif d.type==3 then idx=u16(blob,p) or 0;p=p+2 end
      -- Preserve PNMTXIDX. Enveloped HSD vertices use this value (in multiples
      -- of three GX matrix rows) to select their bind joint/envelope.
      if d.attr==0 and idx~=nil then out[0]={idx} end
    elseif d.type==0 then
    elseif d.type==1 then
      if d.attr==11 or d.attr==12 then
        -- Direct vertex colors are packed GX colors, not four generic numeric
        -- components. We do not need the color for CBE geometry, but consuming
        -- the exact packed width is critical or every following attribute/vertex
        -- is decoded at the wrong byte offset.
        if preserveColors then out[d.attr],p=packedVertexColor(blob,p,d.ctype)
        else p=p+colorDirectBytes(d.ctype) end
      else
        local v;v,p=direct(d,blob,p);out[d.attr]=v
      end
    elseif d.type==2 then
      local idx=blob:byte(p) or 0;p=p+1
      local dataIdx=(d.attr==9 and posMap and posMap[idx]) or idx
      out[d.attr]=indexed(d,dataIdx,blob,preserveColors)
      -- GX_NRM_NBT3 encodes THREE independent indices in the display list.
      -- CBE only needs the first (normal) vector for lighting, but we must
      -- consume the binormal+tangent indices to keep the stream aligned.
      if (d.attr==10 or d.attr==25) and d.count==2 then p=p+2 end
    elseif d.type==3 then
      local idx=u16(blob,p) or 0;p=p+2
      local dataIdx=(d.attr==9 and posMap and posMap[idx]) or idx
      out[d.attr]=indexed(d,dataIdx,blob,preserveColors)
      if (d.attr==10 or d.attr==25) and d.count==2 then p=p+4 end
    else return nil,p end
  end
  return out,p
end
-- Legacy 1.5.20 helper-geometry heuristic. The old build tried to identify
-- invisible/helper meshes from texture presence, relative size and distance after
-- decoding. That can remove legitimate small untextured parts and is no longer
-- part of normal Pokemon extraction. Native JOBJ render-pass flags are now the
-- source of truth; this function remains only behind opts.filterPlaceholders for
-- controlled diagnostics.
local PLACEHOLDER_MAX_VERT_FRACTION=0.15
local PLACEHOLDER_MIN_DISTANCE_RATIO=1.5
local function groupBounds(verts)
  local min,max={1e30,1e30,1e30},{-1e30,-1e30,-1e30}
  for _,v in ipairs(verts) do
    for k=1,3 do if v[k]<min[k] then min[k]=v[k] end;if v[k]>max[k] then max[k]=v[k] end end
  end
  return min,max
end
local function filterPlaceholderGroups(groups)
  if #groups<2 then return groups,{} end
  local totalVerts=0
  for _,g in ipairs(groups) do totalVerts=totalVerts+#g.vertices end
  if totalVerts==0 then return groups,{} end
  -- Anchor on the group with the most vertices, textured or not: on a real
  -- model that is, overwhelmingly, going to be part of the body, and it does
  -- not depend on any group actually being textured (a fully vertex-colored
  -- source model would have none).
  local mainIdx,mainCount=1,#groups[1].vertices
  for i,g in ipairs(groups) do if #g.vertices>mainCount then mainIdx,mainCount=i,#g.vertices end end
  local mainMin,mainMax=groupBounds(groups[mainIdx].vertices)
  local mainCenter={(mainMin[1]+mainMax[1])/2,(mainMin[2]+mainMax[2])/2,(mainMin[3]+mainMax[3])/2}
  local mainExtent=sqrt((mainMax[1]-mainMin[1])^2+(mainMax[2]-mainMin[2])^2+(mainMax[3]-mainMin[3])^2)
  if mainExtent<1e-6 then return groups,{} end
  local kept,removed={},{}
  for i,g in ipairs(groups) do
    local isPlaceholder=false
    if i~=mainIdx and not g.texture then
      local frac=#g.vertices/totalVerts
      if frac<PLACEHOLDER_MAX_VERT_FRACTION then
        local gmin,gmax=groupBounds(g.vertices)
        local gcenter={(gmin[1]+gmax[1])/2,(gmin[2]+gmax[2])/2,(gmin[3]+gmax[3])/2}
        local d=sqrt((gcenter[1]-mainCenter[1])^2+(gcenter[2]-mainCenter[2])^2+(gcenter[3]-mainCenter[3])^2)
        if d>mainExtent*PLACEHOLDER_MIN_DISTANCE_RATIO then isPlaceholder=true end
      end
    end
    if isPlaceholder then
      removed[#removed+1]={index=i,vertices=#g.vertices}
    else
      kept[#kept+1]=g
    end
  end
  return kept,removed
end
-- Native HSD envelope skinning. PNMTXIDX selects an entry in the POBJ-local
-- envelope palette (slot * 3). Each envelope entry stores one or more
-- {HSD_JOBJ*, weight} pairs. Runtime deformation uses the joint's current world
-- matrix, its stored inverse-bind matrix, and (when present) the mesh owner's
-- envelope coordinate system. A 100% single-bone envelope hanging directly from
-- SKELETON_ROOT is a special runtime fast path: it uses joint.world with no IBM.
local MAX_ENVELOPE_BONES=24
local JOBJ_SKELETON=0x00000001
local JOBJ_SKELETON_ROOT=0x00000002

local function inverseBindFor(budget,jobj)
  local cached=budget.inverseBindResolved[jobj]
  if cached~=nil then return cached or ident() end
  local j=jobj
  while j do
    local m=budget.inverseBindByJobj[j]
    if m then budget.inverseBindResolved[jobj]=m;return m end
    j=budget.parentByJobj[j]
  end
  budget.inverseBindMissing=(budget.inverseBindMissing or 0)+1
  -- Native envelopes are expected to reference a joint with a stored IBM. If
  -- neither that joint nor an ancestor has one, HSD's importer-side semantics
  -- reduce to identity rather than inventing an inverse from the current pose.
  -- Using the posed world transform here feeds animation back into the bind
  -- correction and is exactly the kind of frame-dependent drift we must avoid.
  local m=ident()
  budget.inverseBindResolved[jobj]=m
  return m
end

local function findSkeletonOwner(budget,jobj)
  local j=jobj
  while j do
    local flags=budget.flagsByJobj[j] or 0
    if hasFlag(flags,JOBJ_SKELETON_ROOT) or hasFlag(flags,JOBJ_SKELETON) then return j end
    j=budget.parentByJobj[j]
  end
end

-- Mirrors HSD's _HSD_mkEnvelopeModelNodeMtx semantics used by native PKX
-- models. This owner-relative coordinate system is the piece the old CBE
-- Pokemon path omitted entirely; omitting it disassembles even 100%-single-bone
-- envelopes when the mesh owner is below a skeleton node.
local function envelopeCoordSystem(budget,ownerJobj)
  if not ownerJobj then return nil end
  local cached=budget.envelopeCoordCache[ownerJobj]
  if cached~=nil then return cached or nil end
  local ownerFlags=budget.flagsByJobj[ownerJobj] or 0
  if hasFlag(ownerFlags,JOBJ_SKELETON_ROOT) then budget.envelopeCoordCache[ownerJobj]=false;return nil end
  local skel=findSkeletonOwner(budget,ownerJobj)
  if not skel then budget.envelopeCoordCache[ownerJobj]=false;return nil end
  local ownerWorld=budget.worldByJobj[ownerJobj] or ident()
  local ownerInvBind=inverseBindFor(budget,ownerJobj)
  local coord
  if skel==ownerJobj then
    coord=invertAffine(ownerInvBind)
  elseif hasFlag(budget.flagsByJobj[skel] or 0,JOBJ_SKELETON_ROOT) then
    coord=mul(invertAffine(budget.worldByJobj[skel] or ident()),ownerWorld)
  else
    local skelWorld=budget.worldByJobj[skel] or ident()
    coord=mul(invertAffine(mul(skelWorld,ownerInvBind)),ownerWorld)
  end
  budget.envelopeCoordCache[ownerJobj]=coord
  return coord
end

local function legacyEnvelopeWorld(a,pobj,v,defaultWorld,budget)
  local raw=v[0] and tonumber(v[0][1]) or 0;local index=floor(raw/3)
  local tablePtr=a:ptr(pobj+0x14);local envelope=tablePtr and a:ptr(tablePtr+index*4) or nil
  if not envelope then return defaultWorld end
  local bones={};local p=envelope
  for _=1,MAX_ENVELOPE_BONES do
    local bone=a:ptr(p);if not bone then break end
    local w=f32(a.blob,p+4+1);local bw=budget.worldByJobj[bone]
    if bw and w and w>0 then bones[#bones+1]={bone=bone,bw=bw,w=w} end;p=p+8
  end
  if #bones==0 then return defaultWorld end
  if #bones==1 then return bones[1].bw end
  local acc,total={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},0
  for _,e in ipairs(bones) do for k=1,16 do acc[k]=acc[k]+e.bw[k]*e.w end;total=total+e.w end
  if total>1e-6 and abs(total-1)>1e-4 then for k=1,16 do acc[k]=acc[k]/total end end
  return acc
end

local function envelopeWorld(a,pobj,v,defaultWorld,budget,ownerJobj)
  if budget.skinFix==false then return legacyEnvelopeWorld(a,pobj,v,defaultWorld,budget) end
  local raw=v[0] and tonumber(v[0][1]) or 0
  local index=floor(raw/3)
  local byPobj=budget.envelopeWorldCache[pobj]
  if not byPobj then byPobj={};budget.envelopeWorldCache[pobj]=byPobj end
  local cached=byPobj[index]
  if cached~=nil then return cached or defaultWorld end
  local tablePtr=a:ptr(pobj+0x14)
  local envelope=tablePtr and a:ptr(tablePtr+index*4) or nil
  if not envelope then byPobj[index]=false;return defaultWorld end

  local entries={};local p=envelope
  for _=1,MAX_ENVELOPE_BONES do
    local bone=a:ptr(p);if not bone then break end
    local w=f32(a.blob,p+4+1)
    if budget.worldByJobj[bone] and w and w>0 then entries[#entries+1]={bone=bone,w=w} end
    p=p+8
  end
  if #entries==0 then byPobj[index]=false;return defaultWorld end

  local coord=envelopeCoordSystem(budget,ownerJobj)
  local matrix
  if #entries==1 and entries[1].w>=0.999999 then
    local e=entries[1];matrix=e and budget.worldByJobj[e.bone]
    if coord then
      matrix=mul(mul(matrix,inverseBindFor(budget,e.bone)),coord)
      budget.singleEnvelopeCoord=(budget.singleEnvelopeCoord or 0)+1
    else
      budget.singleEnvelopeNoCoord=(budget.singleEnvelopeNoCoord or 0)+1
    end
  else
    local acc={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
    for _,e in ipairs(entries) do
      local contribution=mul(budget.worldByJobj[e.bone],inverseBindFor(budget,e.bone))
      for k=1,16 do acc[k]=acc[k]+contribution[k]*e.w end
    end
    matrix=coord and mul(acc,coord) or acc
    budget.envelopeBlendsMulti=(budget.envelopeBlendsMulti or 0)+1
  end
  budget.envelopeBlends=(budget.envelopeBlends or 0)+1
  if coord then budget.envelopeCoordEntries=(budget.envelopeCoordEntries or 0)+1 end
  byPobj[index]=matrix
  return matrix
end
local function triangles(kind,verts,out)
  if kind==0x90 then for i=1,#verts-2,3 do out[#out+1]={verts[i],verts[i+1],verts[i+2]} end
  elseif kind==0x80 then for i=1,#verts-3,4 do out[#out+1]={verts[i],verts[i+1],verts[i+2]};out[#out+1]={verts[i],verts[i+2],verts[i+3]} end
  elseif kind==0x98 then for i=3,#verts do if i%2==1 then out[#out+1]={verts[i-2],verts[i-1],verts[i]} else out[#out+1]={verts[i-1],verts[i-2],verts[i]} end end
  elseif kind==0xA0 then for i=3,#verts do out[#out+1]={verts[1],verts[i-1],verts[i]} end end
end
local POBJ_SHAPEANIM=0x1000
local function appendDescs(dst,src)
  -- ShapeSet descriptors may point INTO the base descriptor array. GX
  -- consumes one attribute per enum, never the duplicate tail of that array.
  local seen={};for _,d in ipairs(dst) do seen[d.attr]=true end
  for _,d in ipairs(src or {}) do
    if not seen[d.attr] then dst[#dst+1]=d;seen[d.attr]=true end
  end
  table.sort(dst,function(a,b) return a.attr<b.attr end)
end
local function shapeVertexMap(a,shape)
  if not shape then return nil end
  local count=u32(a.blob,shape+0x04+1) or 0
  if count<=0 or count>200000 then return nil end
  local tables=a:ptr(shape+0x0C);if not tables then return nil end
  local first=a:ptr(tables);if not first then return nil end
  local map={}
  for i=0,count-1 do
    local v=s16(a.blob,first+i*2+1);if v==nil then break end
    map[i]=v>=0 and v or 0
  end
  return map
end
local function parsePobjDescs(a,pobj)
  local basePtr=a:ptr(pobj+0x08);if not basePtr then return {},nil end
  local out=parseDescs(a,basePtr)
  local flags=u16(a.blob,pobj+0x0C+1) or 0
  local map=nil
  if flags%0x2000>=POBJ_SHAPEANIM then
    local shape=a:ptr(pobj+0x14)
    if shape then
      -- Match SysDolphin/HSDLib HSD_POBJ.ToGXAttributes(): shape-animated
      -- polygons concatenate their ShapeSet vertex and normal descriptors onto
      -- the base POBJ attribute list. Omitting these descriptors makes CBE read
      -- too few bytes per display-list vertex and desynchronizes the command
      -- stream after the first animated vertex. Static arena POBJs don't hit
      -- this path, which is why the bug presented as trainer-only.
      local vertexPtr=a:ptr(shape+0x08)
      if vertexPtr and vertexPtr~=basePtr then appendDescs(out,parseDescs(a,vertexPtr)) end
      local normalPtr=a:ptr(shape+0x14)
      if normalPtr then appendDescs(out,parseDescs(a,normalPtr)) end
      map=shapeVertexMap(a,shape)
    end
  end
  return out,map
end
local function parseDisplay(a,pobj,world,budget,ownerJobj)
  budget=budget or {displayOps=0,vertices=0,maxDisplayOps=80000,maxVertices=30000}
  local blob=a.blob;local pobjFlags=u16(blob,pobj+0x0C+1) or 0
  if pobjFlags%0x2000>=POBJ_SHAPEANIM then budget.shapePobjs=(budget.shapePobjs or 0)+1 end
  if pobjFlags%0x4000>=0x2000 then budget.envelopePobjs=(budget.envelopePobjs or 0)+1 end
  local nDisplay=u16(blob,pobj+0x0E+1) or 0;local dl=a:ptr(pobj+0x10)
  if not dl or nDisplay==0 then return {} end
  local descs,posMap=parsePobjDescs(a,pobj);if budget.shapeIndexMap==false then posMap=nil end;if #descs==0 then return {} end
  local byteLen=nDisplay*32
  if byteLen<=0 or byteLen>8*1024*1024 then budget.exhausted="display-list byte budget";return {} end
  local pend=math.min(a.base+a.fileSize,dl+byteLen);local p=dl+1;local tris={};local guard=0
  while p+2<=pend and guard<8192 and not budget.exhausted do
    guard=guard+1;local op=blob:byte(p) or 0;p=p+1
    if op~=0 then
      local kind=floor(op/8)*8;local n=u16(blob,p) or 0;p=p+2
      if n>20000 then budget.exhausted="primitive vertex count";break end
      local vs={}
      for _=1,n do
        if p>pend then break end
        budget.displayOps=budget.displayOps+1
        if budget.checkpoint and budget.displayOps%128==0 then budget.checkpoint() end
        if budget.displayOps>(budget.maxDisplayOps or 80000) then budget.exhausted="display decode operation budget";break end
        local v;v,p=readVertex(descs,blob,p,posMap,budget.preserveVertexColors);if not v then break end;vs[#vs+1]=v
      end
      if budget.exhausted then break end
      triangles(kind,vs,tris)
      if #tris>20000 then budget.exhausted="triangle budget";break end
    end
  end
  if guard>=8192 then budget.exhausted="display command budget" end
  local rows={}
  for ti,tri in ipairs(tris) do
    if budget.checkpoint and ti%64==0 then budget.checkpoint() end
    local firstRow=#rows
    for _,v in ipairs(tri) do
      if budget.vertices+#rows>=(budget.maxVertices or 30000) then budget.exhausted="mesh vertex budget";break end
      local pos=v[9];if pos and #pos>=2 then
        local vertexWorld
        if pobjFlags%0x4000>=0x2000 then
          vertexWorld=envelopeWorld(a,pobj,v,world,budget,ownerJobj)
        else
          vertexWorld=world
        end
        local x,y,z=pos[1] or 0,pos[2] or 0,pos[3] or 0;local wx,wy,wz=point(vertexWorld,x,y,z)
        local uv=v[13] or {0,0};local nr=v[10] or v[25] or {0,1,0};local nx,ny,nz=normal(vertexWorld,nr[1] or 0,nr[2] or 1,nr[3] or 0)
        local color=budget.preserveVertexColors and v[11]
        if color then
          -- Canonical extended row: XYZ, UV, RGBA, authored normal XYZ.
          rows[#rows+1]={wx,wy,wz,uv[1] or 0,uv[2] or 0,color[1],color[2],color[3],color[4],nx,ny,nz}
        else
          rows[#rows+1]={wx,wy,wz,uv[1] or 0,uv[2] or 0,nx,ny,nz}
        end
      end
    end
    if #rows-firstRow~=3 then
      for i=#rows,firstRow+1,-1 do rows[i]=nil end
      budget.incompleteTriangles=(budget.incompleteTriangles or 0)+1
    end
    if budget.exhausted then break end
  end
  return rows
end

-- Retail GSmodel bound display-list walk. This is intentionally separate from
-- parseDisplay(): GSmodelParse feeds every submitted GX position to its bound
-- callback, including points/lines and source shadow-pass geometry, while the
-- visible CBE path triangulates renderable surfaces and applies presentation
-- cleanup. Reusing the visible rows here would therefore produce the wrong AABB.
local RETAIL_POBJ_SKIP=0x0800
local RETAIL_POBJ_SHAPE=0x1000
local RETAIL_POBJ_ENVELOPE=0x2000
local function retailStrictInverse(m)
  if type(m)~="table" then return nil end
  local a,b,c,tx=m[1],m[2],m[3],m[4]
  local d,e,f,ty=m[5],m[6],m[7],m[8]
  local g,h,i,tz=m[9],m[10],m[11],m[12]
  if not (finite(a) and finite(b) and finite(c) and finite(tx) and finite(d) and finite(e) and finite(f)
      and finite(ty) and finite(g) and finite(h) and finite(i) and finite(tz)) then return nil end
  local det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
  -- Retail PSMTXInverse/HSD_MtxInverseConcat cannot produce a defined matrix
  -- from a singular source. Fail closed instead of inheriting invertAffine()'s
  -- renderer-only identity fallback.
  if not finite(det) or abs(det)<1e-12 then return nil end
  local id=1/det
  local A,B,C=(e*i-f*h)*id,(c*h-b*i)*id,(b*f-c*e)*id
  local D,E,F=(f*g-d*i)*id,(a*i-c*g)*id,(c*d-a*f)*id
  local G,H,I=(d*h-e*g)*id,(b*g-a*h)*id,(a*e-b*d)*id
  return {A,B,C,-(A*tx+B*ty+C*tz),D,E,F,-(D*tx+E*ty+F*tz),G,H,I,-(G*tx+H*ty+I*tz),0,0,0,1}
end
local function retailEnvelopeNodeMatrix(budget,ownerJobj)
  if not ownerJobj then return nil,"retail-bound envelope owner JObj unavailable" end
  local ownerFlags=budget.flagsByJobj[ownerJobj] or 0
  -- _HSD_mkEnvelopeModelNodeMtx returns NULL for a skeleton root. `false` is a
  -- deliberate NULL sentinel so nil remains reserved for a failed exact build.
  if hasFlag(ownerFlags,JOBJ_SKELETON_ROOT) then return false end
  local skeleton=findSkeletonOwner(budget,ownerJobj)
  if not skeleton then return nil,"retail-bound envelope skeleton owner unavailable" end
  local ownerWorld=budget.worldByJobj[ownerJobj]
  local skeletonWorld=budget.worldByJobj[skeleton]
  if not (ownerWorld and skeletonWorld) then return nil,"retail-bound envelope skeleton matrix unavailable" end
  local base
  if skeleton==ownerJobj then
    base=budget.inverseBindByJobj[skeleton]
    if not base then return nil,"retail-bound envelope model-node matrix unavailable" end
  elseif hasFlag(budget.flagsByJobj[skeleton] or 0,JOBJ_SKELETON_ROOT) then
    base=skeletonWorld
  else
    local envelopeMtx=budget.inverseBindByJobj[skeleton]
    if not envelopeMtx then return nil,"retail-bound envelope skeleton bind matrix unavailable" end
    base=mul(skeletonWorld,envelopeMtx)
  end
  local inv=retailStrictInverse(base)
  if not inv then return nil,"retail-bound envelope model-node matrix singular" end
  if skeleton==ownerJobj then return inv end
  return mul(inv,ownerWorld)
end
local function retailEnvelopePalette(a,pobj,budget,ownerJobj)
  budget.retailEnvelopePalettes=budget.retailEnvelopePalettes or {}
  local cached=budget.retailEnvelopePalettes[pobj]
  if cached then return cached end
  local tablePtr=a:ptr(pobj+0x14)
  if not tablePtr then return nil,"retail-bound envelope descriptor palette unavailable" end
  local node,nodeWhy=retailEnvelopeNodeMatrix(budget,ownerJobj)
  if node==nil and nodeWhy then return nil,nodeWhy end
  local palette={}
  for slot=0,9 do
    local desc=a:ptr(tablePtr+slot*4)
    if not desc then break end
    local firstBone=a:ptr(desc)
    local firstWeight=f32(a.blob,desc+4+1)
    if not firstBone then return nil,"retail-bound envelope palette entry is empty" end
    if not finite(firstWeight) then return nil,"retail-bound envelope weight invalid" end
    local source
    if firstWeight>=1 then
      local world=budget.worldByJobj[firstBone]
      if not world then return nil,"retail-bound envelope joint reference unresolved" end
      source=world
      if node then
        local envelopeMtx=budget.inverseBindByJobj[firstBone]
        if not envelopeMtx then return nil,"retail-bound envelope joint bind matrix unavailable" end
        source=mul(world,envelopeMtx)
      end
    else
      -- Retail does not filter, clamp, or renormalize weights in this branch.
      -- HSD_MtxScaledAdd accumulates exactly the twelve affine matrix scalars.
      local acc={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1}
      local p=desc;local count=0
      while count<256 do
        local bone=a:ptr(p)
        if not bone then break end
        local weight=f32(a.blob,p+4+1)
        local world=budget.worldByJobj[bone]
        local envelopeMtx=budget.inverseBindByJobj[bone]
        if not finite(weight) then return nil,"retail-bound envelope weight invalid" end
        if not world then return nil,"retail-bound envelope joint reference unresolved" end
        if not envelopeMtx then return nil,"retail-bound envelope joint bind matrix unavailable" end
        local contribution=mul(world,envelopeMtx)
        for k=1,12 do acc[k]=acc[k]+contribution[k]*weight end
        count=count+1;p=p+8
      end
      if count==0 then return nil,"retail-bound envelope palette entry is empty" end
      if count>=256 and a:ptr(p) then return nil,"retail-bound envelope entry exceeds audit budget" end
      source=acc
      budget.retailEnvelopeMulti=(budget.retailEnvelopeMulti or 0)+1
    end
    if node then source=mul(source,node) end
    -- In the supported non-instance GSmodelParse path, the first matrix argument
    -- to _modelParseJObjDispSub is the identity external obj_mtx. Therefore the
    -- final PSMTXConcat(vmtx, source) is source unchanged; owner pmtx is NOT used.
    palette[slot]=source
  end
  if not palette[0] then return nil,"retail-bound envelope palette contains no matrices" end
  budget.retailEnvelopePalettes[pobj]=palette
  budget.retailEnvelopePaletteCount=(budget.retailEnvelopePaletteCount or 0)+1
  return palette
end
local function retailScalarWidth(ctype)
  if ctype==0 or ctype==1 then return 1 end
  if ctype==2 or ctype==3 then return 2 end
  if ctype==4 then return 4 end
  return -1
end
local function retailDirectWidth(d)
  -- Mirror _dlParseVertex's cursor arithmetic, not the render decoder's
  -- semantic component counts. In particular direct NRM/NBT records use the
  -- parser's type_flag multiplication, which is intentionally different from
  -- the indexed NBT/NBT3 convenience decoding in readVertex().
  if d.attr==11 or d.attr==12 then
    if d.ctype<0 or d.ctype>5 then return -1 end
    return colorDirectBytes(d.ctype)
  end
  local sz=retailScalarWidth(d.ctype)
  if sz<0 then return -1 end
  if d.attr==9 then return sz*(d.count==0 and 2 or 3) end
  if d.attr==10 then return sz*(d.count==0 and 3 or 1) end
  if d.attr==25 then return sz*(d.count==1 and 3 or 1) end
  if d.attr>=13 and d.attr<=20 then return sz*(d.count==0 and 1 or 2) end
  return -1
end
local function retailDobjPassFlag(renderFlags)
  -- HSD DObjLoad: rendermode & 0x60000000 maps exactly to one runtime pass bit.
  local bit29=hasFlag(renderFlags,0x20000000)
  local bit30=hasFlag(renderFlags,0x40000000)
  if bit30 and bit29 then return 0x04,"xlu" end
  if bit30 then return 0x08,"texedge" end
  if bit29 then return nil,"unsupported-rendermode-class-0x20000000" end
  return 0x02,"opa"
end
local function retailJobjHasPass(flags,dobjPass)
  if dobjPass==0x02 then return hasFlag(flags,0x00040000) end
  if dobjPass==0x04 then return hasFlag(flags,0x00080000) end
  if dobjPass==0x08 then return hasFlag(flags,0x00100000) end
  return false
end
local function retailBoundDisplay(a,pobj,world,budget,ownerJobj)
  local blob=a.blob
  local pobjFlags=u16(blob,pobj+0x0C+1) or 0
  if hasFlag(pobjFlags,RETAIL_POBJ_SKIP) then
    budget.skippedPobj800=(budget.skippedPobj800 or 0)+1
    return true
  end
  -- Equivalent to flags & 0x3000 without depending on a bit library.
  local mode=hasFlag(pobjFlags,0x2000) and (hasFlag(pobjFlags,0x1000) and 0x3000 or 0x2000)
    or (hasFlag(pobjFlags,0x1000) and 0x1000 or 0)
  if mode~=0 and mode~=RETAIL_POBJ_SHAPE and mode~=RETAIL_POBJ_ENVELOPE then
    budget.exhausted="retail-bound unsupported PObj matrix mode"
    return false
  end
  if mode==RETAIL_POBJ_SHAPE then budget.shapePobjs=(budget.shapePobjs or 0)+1 end
  if mode==RETAIL_POBJ_ENVELOPE then budget.envelopePobjs=(budget.envelopePobjs or 0)+1 end

  local nDisplay=u16(blob,pobj+0x0E+1) or 0
  local dl=a:ptr(pobj+0x10)
  if not dl or nDisplay==0 then return true end
  local basePtr=a:ptr(pobj+0x08)
  local descs=basePtr and parseDescs(a,basePtr) or {}
  if #descs==0 then budget.exhausted="retail-bound vertex descriptors unavailable";return false end
  local envelopePalette=nil
  if mode==RETAIL_POBJ_ENVELOPE then
    -- _modelParseLoadEnvelopeMatrix runs for every visible envelope PObj before
    -- the bound callback, even when the display list has no PNMTXIDX attribute.
    -- Build/validate it unconditionally so malformed source cannot be accepted
    -- merely because the callback would not later index the palette.
    local why
    envelopePalette,why=retailEnvelopePalette(a,pobj,budget,ownerJobj)
    if not envelopePalette then budget.exhausted=why or "retail-bound envelope palette unavailable";return false end
  end
  local byteLen=nDisplay*32
  if byteLen<=0 or byteLen>8*1024*1024 then budget.exhausted="retail-bound display-list byte budget";return false end
  local pend=math.min(a.base+a.fileSize,dl+byteLen)
  local p=dl+1
  local commandGuard=0
  local primitive={ [0x80]=true,[0x90]=true,[0x98]=true,[0xA0]=true,[0xA8]=true,[0xB0]=true,[0xB8]=true }
  while p<=pend and not budget.exhausted do
    commandGuard=commandGuard+1
    if commandGuard>(budget.maxCommands or 8192) then budget.exhausted="retail-bound display command budget";break end
    local raw=blob:byte(p);if raw==nil then break end;p=p+1
    if raw==0 then
      -- GX_NOP.
    elseif raw==0x61 then
      -- The recovered GSgfx parser carries an explicit BP-register command
      -- branch. PObj display lists normally contain only primitives, but when
      -- present this command owns four payload bytes and submits no positions.
      if p+3>pend then budget.exhausted="retail-bound truncated BP command";break end
      p=p+4
    else
      local kind=floor(raw/8)*8
      if not primitive[kind] then
        budget.exhausted=("retail-bound unsupported display command 0x%02X"):format(raw)
        break
      end
      if p+1>pend then budget.exhausted="retail-bound truncated primitive header";break end
      local count=u16(blob,p) or 0;p=p+2
      if count>20000 then budget.exhausted="retail-bound primitive vertex count";break end
      for _=1,count do
        budget.displayOps=(budget.displayOps or 0)+1
        if budget.checkpoint and budget.displayOps%128==0 then budget.checkpoint() end
        if budget.displayOps>(budget.maxDisplayOps or 80000) then budget.exhausted="retail-bound display decode operation budget";break end
        local matrixByte=nil
        local pos=nil
        local hasPnMtx=false
        for _,d in ipairs(descs) do
          local dataPtr=nil
          if d.attr>=0 and d.attr<=8 then
            -- GSgfxParseDisplayList consumes matrix-index attributes as one raw
            -- byte regardless of the descriptor attr_type. _modelBoundVertex
            -- uses PNMTXIDX / 3 as the envelope-palette slot.
            local v=blob:byte(p)
            if v==nil or p>pend then budget.exhausted="retail-bound truncated matrix index";break end
            if d.attr==0 then matrixByte=v;hasPnMtx=true end
            p=p+1
          elseif d.type==1 then
            dataPtr=p
            local width=retailDirectWidth(d)
            if width<0 or p+width-1>pend then budget.exhausted="retail-bound truncated direct vertex attribute";break end
            p=p+width
          else
            -- Retail treats INDEX8 only when attr_type == 2; every other
            -- non-direct descriptor takes a 16-bit index.
            local index
            if d.type==2 then
              index=blob:byte(p);if index==nil or p>pend then budget.exhausted="retail-bound truncated index8";break end;p=p+1
            else
              if p+1>pend then budget.exhausted="retail-bound truncated index16";break end
              index=u16(blob,p);p=p+2
            end
            if d.array and index then dataPtr=d.array+index*(d.stride or 0)+1 end
          end
          if d.attr==9 then
            if not dataPtr then budget.exhausted="retail-bound position array unavailable";break end
            -- _modelBoundVertex receives the raw source position pointer and
            -- reads three float32 values directly. Mirror that contract rather
            -- than converting through CBE's generic GX component decoder.
            local x,y,z=f32(blob,dataPtr),f32(blob,dataPtr+4),f32(blob,dataPtr+8)
            if not (finite(x) and finite(y) and finite(z)) then budget.exhausted="retail-bound non-float position";break end
            pos={x,y,z}
          end
        end
        if budget.exhausted then break end
        if mode==RETAIL_POBJ_SHAPE and hasPnMtx then
          -- Retail passes NULL as the matrix palette for shape PObjs. A shape
          -- display list carrying PNMTXIDX would therefore not have a defensible
          -- offline matrix source here; fail closed instead of inventing one.
          budget.exhausted="retail-bound shape PNMTXIDX unsupported"
          break
        end
        if pos then
          local vertexWorld=world
          if mode==RETAIL_POBJ_ENVELOPE and hasPnMtx then
            local slot=floor((matrixByte or 0)/3)
            vertexWorld=envelopePalette[slot]
            if not vertexWorld then budget.exhausted="retail-bound envelope PNMTXIDX references unbuilt palette slot";break end
          elseif mode==0 and hasPnMtx then
            -- Rigid PObjs still use the two-matrix HSD palette when PNMTXIDX
            -- is present: slot 0 is the current PObj position matrix; slot 1,
            -- when u.jobj is non-null, is obj_mtx * referencedJObj->mtx.
            -- Instances/billboards are rejected above, so GSmodelParse's
            -- obj_mtx is identity and the referenced source JObj world matrix
            -- is the exact slot-1 value here.
            local slot=floor((matrixByte or 0)/3)
            if slot==0 then
              vertexWorld=world
            elseif slot==1 then
              local ref=a:ptr(pobj+0x14)
              vertexWorld=ref and budget.worldByJobj[ref] or nil
              if not vertexWorld then budget.exhausted="retail-bound rigid PNMTXIDX slot 1 source JObj unavailable";break end
            else
              budget.exhausted="retail-bound rigid PNMTXIDX exceeds two-matrix palette";break
            end
          end
          local x,y,z=point(vertexWorld,pos[1],pos[2],pos[3])
          if not (finite(x) and finite(y) and finite(z)) then budget.exhausted="retail-bound transformed position invalid";break end
          for k,v in ipairs({x,y,z}) do
            if v<budget.min[k] then budget.min[k]=v end
            if v>budget.max[k] then budget.max[k]=v end
          end
          budget.vertices=(budget.vertices or 0)+1
          if budget.vertices>(budget.maxVertices or 200000) then budget.exhausted="retail-bound vertex budget";break end
        end
      end
    end
  end
  return not budget.exhausted
end
local function decodeTextureObject(a,tobj,slot,sourceTextureState,metadataOnly)
  if not tobj then return nil end
  local img=a:ptr(tobj+0x4C);if not img then return nil end
  local b=a.blob;local data=a:ptr(img);local w,h=u16(b,img+5),u16(b,img+7);local fmt=u32(b,img+9)
  if not data or not w or not h or not fmt or w==0 or h==0 or w>2048 or h>2048 then return nil end
  local n
  if not metadataOnly then
    n=GX.dataSize(w,h,fmt);if data+n>a.base+a.fileSize then return nil end
  end
  local palette,palFmt,pp=nil,nil,nil;local tlut=a:ptr(tobj+0x50)
  if tlut then pp=a:ptr(tlut);palFmt=u32(b,tlut+5);local count=u16(b,tlut+0x0C+1) or 0;if pp and count>0 and pp+count*2<=a.base+a.fileSize then palette=b:sub(pp+1,pp+count*2) end end
  -- A venue commonly references the same large atlas from many DOBJ groups.
  -- Pure-Lua GX decoding is expensive, so cache immutable decoded pixels per
  -- archive/image/palette identity while retaining each TOBJ's own render state.
  local rgba
  if not metadataOnly then
    a._decodedTextures=a._decodedTextures or {}
    local key=("%d:%d:%d:%d:%d"):format(data,w,h,fmt,pp or -1)
    rgba=a._decodedTextures[key]
    if not rgba then
      local ok,decoded=pcall(GX.decode,b:sub(data+1,data+n),w,h,fmt,palette,palFmt)
      if not ok then return nil end
      rgba=decoded;a._decodedTextures[key]=rgba
    end
  end
  -- Preserve source TOBJ metadata. The current actor shader only consumes the
  -- image/wrap state, but keeping the remaining values with the group prevents
  -- us from having to rediscover which texture stage was actually enabled.
  local wrapS=u32(b,tobj+0x34+1)
  local wrapT=u32(b,tobj+0x38+1)
  local flags=u32(b,tobj+0x40+1) or 0
  local texture={
    w=w,h=h,format=fmt,rgba=rgba,dataOffset=data-a.data,
    wrapS=wrapS,wrapT=wrapT,slot=slot or 0,
    texgen=u32(b,tobj+0x0C+1) or 0,flags=flags,
  }
  local function vector(off,default)
    local v={}
    for k=1,3 do local n=f32(b,tobj+off+(k-1)*4+1);v[k]=finite(n) and n or default end
    return v
  end
  -- Coordinate generation is part of the texture identity, not optional sampler
  -- decoration.  Several retail Pokemon (Steelix is the visible regression) use
  -- HSD_TObj TEX_COORD_REFLECTION: their display lists intentionally carry UV
  -- 0,0 because GX generates S/T from the view-space normal.  Dropping this
  -- metadata turns the whole body into one dark texel.  Preserve the tiny SRT /
  -- coord payload even for the ordinary actor path; sourceTextureState still
  -- gates the larger sampler/LOD fidelity block below.
  texture.coordinateMode=flags%16
  texture.rotation=vector(0x10,0);texture.scale=vector(0x1C,1);texture.translation=vector(0x28,0)
  texture.repeatS=b:byte(tobj+0x3C+1) or 1;texture.repeatT=b:byte(tobj+0x3D+1) or 1
  -- Dense actor pose extraction keeps the rest of its original metadata cost.
  if sourceTextureState~=true then return texture end
  local blending=f32(b,tobj+0x44+1)
  texture.colorMap=floor(flags/0x10000)%16;texture.alphaMap=floor(flags/0x100000)%16
  texture.blending=finite(blending) and blending or 1
  -- HSD_TObjDesc / HSD_ImageDesc / HSD_TexLODDesc sampler state. Retail HSD
  -- passes these directly to GXInitTexObjLOD; preserving them lets actor
  -- runtimes distinguish source nearest/linear filtering instead of applying a
  -- blanket host-side linear/aniso policy to every face/clothing texture.
  texture.magFilt=u32(b,tobj+0x48+1)
  texture.mipmap=(u32(b,img+0x0C+1) or 0)~=0
  texture.minLOD=f32(b,img+0x10+1);texture.maxLOD=f32(b,img+0x14+1)
  local lod=a:ptr(tobj+0x54)
  if lod and lod+0x0F<a.base+a.fileSize then
    texture.minFilt=u32(b,lod+1)
    texture.lodBias=f32(b,lod+0x04+1)
    texture.biasClamp=(b:byte(lod+0x08+1) or 0)~=0
    texture.edgeLOD=(b:byte(lod+0x09+1) or 0)~=0
    texture.maxAnisotropy=u32(b,lod+0x0C+1)
  else
    -- GC6E01's SysDolphin default HSD_TexLODDesc at 0x8036D594 is
    -- {minFilt=GX_LIN_MIP_LIN(5), LODBias=0, clamp=0, edge=0, aniso=1x(0)}.
    texture.minFilt=5;texture.lodBias=0;texture.biasClamp=false;texture.edgeLOD=false;texture.maxAnisotropy=0
  end
  texture.effectiveMinFilt=texture.mipmap and texture.minFilt or ((tonumber(texture.minFilt) or 5)%2)
  return texture
end

-- SysDolphin MakeTextureMtx composes Scale * Rotation * Translation, with
-- inverse UV scale, negated rotation Z/translation XY, and a mirrored-T phase.
-- Ordinary static arena UVs can bake this affine stage without changing the
-- canonical vertex layout. Actors and animated effect extractors do not opt in.
local function textureBaseMatrix(t)
  if not t or t.texgen~=4 then return nil end
  local s,r,p=t.scale or {1,1,1},t.rotation or {0,0,0},t.translation or {0,0,0}
  local rs,rt=tonumber(t.repeatS) or 1,tonumber(t.repeatT) or 1
  if rs<=0 or rt<=0 then return nil end
  local sx=abs(s[1])<1e-10 and 0 or rs/s[1]
  local sy=abs(s[2])<1e-10 and 0 or rt/s[2]
  local tm=localM(0,0,0,1,1,1,-p[1],-(p[2]+(t.wrapT==2 and s[2]/rt or 0)),p[3])
  local rm=localM(r[1],r[2],-r[3],1,1,1,0,0,0)
  local sm=localM(0,0,0,sx,sy,s[3],0,0,0)
  return mul(sm,mul(rm,tm))
end
local function sourceTextureMatrix(t)
  if not t or t.coordinateMode~=0 then return nil end
  return textureBaseMatrix(t)
end
-- SysDolphin HSD_TObj TEX_COORD_REFLECTION (tobj.c::TObjSetupMtx): GX feeds a
-- view-space normal into a 3x4 matrix derived from MakeTextureMtx.  Preserve the
-- exact matrix so runtime can reproduce generated coordinates instead of
-- pretending the display-list UV stream is meaningful.  Identity SRT becomes:
--   S =  .5*Nx + .5
--   T = -.5*Ny + .5
--   Q = 1
local function reflectionTextureMatrix(t)
  if not t or tonumber(t.coordinateMode)~=1 then return nil end
  local m=textureBaseMatrix(t);if not m then return nil end
  local out={0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1}
  for row=0,2 do
    local at=row*4+1
    out[at]=.5*m[at]
    out[at+1]=-.5*m[at+1]
    out[at+2]=0
    out[at+3]=.5*m[at]+.5*m[at+1]+m[at+2]+m[at+3]
  end
  return out
end
local function applySourceTextureState(rows,t,enabled)
  if not enabled then return false end
  local m=sourceTextureMatrix(t)
  -- A varying Q requires projective interpolation in the GPU vertex schema.
  -- Leave reflection/projected stages alone; the audited retail arena UV
  -- stages all have constant Q=1 and are exactly representable as two UVs.
  if not m or abs(m[9])>1e-10 or abs(m[10])>1e-10 then return false end
  local q=m[11]+m[12]
  if abs(q)<1e-10 then return false end
  for _,v in ipairs(rows) do
    local u,w=v[4],v[5]
    v[4]=(m[1]*u+m[2]*w+m[3]+m[4])/q
    v[5]=(m[5]*u+m[6]*w+m[7]+m[8])/q
  end
  return true
end

-- HSD_MOBJ can carry a chain of up to eight TOBJs, while RenderFlags TEX0..TEX7
-- decides which stages are actually sampled. 1.5.24 always decoded the FIRST
-- pointer in the chain even when TEX0 was disabled; that can bind a shadow/
-- auxiliary map as the Pokemon's diffuse image or report an active material as
-- "untextured". Match the native material contract and select the first ENABLED
-- stage instead.
local function firstEnabledTexture(a,mobj,sourceTextureState,metadataOnly)
  if not mobj then return nil end
  local b=a.blob
  local renderFlags=u32(b,mobj+0x04+1) or 0
  local tobj=a:ptr(mobj+0x08)
  local slot=0
  while tobj and slot<8 do
    local enabled=(math.floor(renderFlags/(2^(slot+4)))%2)==1
    if enabled then
      local tex=decodeTextureObject(a,tobj,slot,sourceTextureState,metadataOnly)
      if tex then return tex,tobj end
    end
    tobj=a:ptr(tobj+0x04)
    slot=slot+1
  end
  return nil
end

local function materialInfo(a,mobj)
  if not mobj then return nil end
  local b=a.blob
  local flags=u32(b,mobj+0x04+1) or 0
  local mat=a:ptr(mobj+0x0C)
  local info={
    -- SysDolphin HSD_MOBJ RENDER_MODE bits. Preserve the full word instead of
    -- collapsing it to xlu/no-z; Pokemon materials rely on constant color,
    -- alpha and special shadow/effect passes even when no ordinary texture is
    -- attached.
    renderFlags=flags,
    xlu=(math.floor(flags/0x40000000)%2)==1,
    noz=(math.floor(flags/0x20000000)%2)==1,
    shadow=(math.floor(flags/0x04000000)%2)==1,
    effect=(math.floor(flags/0x02000000)%2)==1,
    useConstant=(math.floor(flags/0x1)%2)==1,
    useVertexColor=(math.floor(flags/0x2)%2)==1,
    useDiffuseLighting=(math.floor(flags/0x4)%2)==1,
    textureMask=math.floor(flags/0x10)%256,
  }
  if mat and mat+0x13<a.base+a.fileSize then
    local function color(off)
      return {(b:byte(mat+off+1) or 255)/255,(b:byte(mat+off+2) or 255)/255,(b:byte(mat+off+3) or 255)/255}
    end
    info.ambient=color(0x00)
    info.diffuse=color(0x04)
    info.specular=color(0x08)
    local alpha=f32(b,mat+0x0C+1);if finite(alpha) then info.alpha=math.max(0,math.min(1,alpha)) end
    local shine=f32(b,mat+0x10+1);if finite(shine) then info.shininess=math.max(0,shine) end
  end
  -- DAT files carry HSD_MObjDesc, whose +0x14 pedesc pointer is copied verbatim
  -- into the live HSD_MObj PE state by MObjLoad. Preserve the 12-byte descriptor
  -- so exact alpha-test/blend/depth semantics can be reproduced instead of
  -- inferring them from RENDER_XLU/NO_ZUPDATE when a material overrides defaults.
  local pe=a:ptr(mobj+0x14)
  if pe and pe+11<a.base+a.fileSize then
    info.pe={
      flags=b:byte(pe+1) or 0,ref0=b:byte(pe+2) or 0,ref1=b:byte(pe+3) or 0,
      dstAlpha=b:byte(pe+4) or 0,type=b:byte(pe+5) or 0,
      srcFactor=b:byte(pe+6) or 0,dstFactor=b:byte(pe+7) or 0,logicOp=b:byte(pe+8) or 0,
      zComp=b:byte(pe+9) or 0,alphaComp0=b:byte(pe+10) or 0,
      alphaOp=b:byte(pe+11) or 0,alphaComp1=b:byte(pe+12) or 0,
    }
  end
  return info
end

local function animClamp01(v)
  v=tonumber(v) or 0
  if v<=0 then return 0 elseif v>=1 then return 1 end
  return v
end
local function animColor8(v)return math.floor(255*animClamp01(v))/255 end
local function animRef8(v)return math.floor(255*animClamp01(v)) end

-- Evaluate one retail HSD material-animation root into DObj-keyed material
-- snapshots. HSD_JObjAddAnimAll pairs the MatAnimJoint and JObj trees, while
-- HSD_DObjAddAnimAll advances DObj and HSD_MatAnim linked lists in lockstep.
-- Keep this deliberately narrow: trainer shaders can reproduce diffuse, alpha,
-- and PE alpha-reference animation exactly. Any active texture animation,
-- renderanim, ambient/specular, destination-alpha, or unknown MObj channel makes
-- the whole clip unavailable rather than presenting a plausible partial result.
local function nativeMaterialPoseRoot(a,root,clipIndex,frame)
  local clips=nativeMaterialAnimations(a,root)
  local ci=math.max(0,math.floor(tonumber(clipIndex) or 0))
  local maroot=clips[ci+1]
  if not maroot then return nil,#clips,("native material animation index %d unavailable (%d source clips)"):format(ci,#clips) end
  local byDobj={};local animated=false;local blocker=nil;local seenJ={}
  local function evalMaterial(dobj,ma)
    local mobj=a:ptr(dobj+0x08)
    local state=materialInfo(a,mobj)
    byDobj[dobj]=state
    if not ma or not state then return end
    if a:ptr(ma+0x08) then blocker="native material animation carries unsupported HSD_TexAnim";return end
    if a:ptr(ma+0x0C) then blocker="native material animation carries unsupported renderanim";return end
    local aobj=a:ptr(ma+0x04);local fd=aobj and a:ptr(aobj+0x08) or nil;local guard=0
    while fd and guard<64 and not blocker do
      guard=guard+1
      local track,keys=decodeFobj(a,fd);local v=fobjValue(keys,frame or 0)
      local affectsMat=(track>=1 and track<=10) and state.diffuse~=nil
      local affectsPe=(track>=11 and track<=13) and state.pe~=nil
      if v~=nil then
        if track>=4 and track<=6 and state.diffuse then
          state.diffuse[track-3]=animColor8(v);animated=true
        elseif track==10 and state.diffuse then
          state.alpha=animClamp01(1-v);animated=true
        elseif track==11 and state.pe then
          state.pe.ref0=animRef8(v);animated=true
        elseif track==12 and state.pe then
          state.pe.ref1=animRef8(v);animated=true
        elseif affectsMat or affectsPe then
          blocker=("native material animation track %d unsupported by trainer renderer"):format(track or -1)
        elseif track<1 or track>13 then
          blocker=("native material animation track %d unknown"):format(track or -1)
        end
      elseif (track>=4 and track<=6 and state.diffuse) or (track==10 and state.diffuse) or ((track==11 or track==12) and state.pe) then
        -- A delayed supported stream is still an authored animation even before
        -- its first key writes a value. Mark the clip animated so later frames
        -- are retained by TrainerExtractor.
        animated=true
      elseif (affectsMat or affectsPe) and not (track==4 or track==5 or track==6 or track==10 or track==11 or track==12) then
        blocker=("native material animation track %d unsupported by trainer renderer"):format(track or -1)
      elseif track<1 or track>13 then
        blocker=("native material animation track %d unknown"):format(track or -1)
      end
      fd=a:ptr(fd)
    end
    if fd and not blocker then blocker="native material animation FObj chain exceeds audit budget" end
  end
  local function pair(j,mj,depth)
    if blocker or not j or seenJ[j] or depth>256 then return end
    seenJ[j]=true
    local dobj=a:ptr(j+0x10);local ma=mj and a:ptr(mj+0x08) or nil;local guard=0
    while dobj and guard<256 and not blocker do
      guard=guard+1;evalMaterial(dobj,ma)
      dobj=a:ptr(dobj+0x04);ma=ma and a:ptr(ma) or nil
    end
    if dobj and not blocker then blocker="native material animation DObj chain exceeds audit budget";return end
    local child=a:ptr(j+0x08);local childMat=mj and a:ptr(mj) or nil;local childGuard=0
    while child and childGuard<256 and not blocker do
      childGuard=childGuard+1;pair(child,childMat,depth+1)
      child=a:ptr(child+0x0C);childMat=childMat and a:ptr(childMat+0x04) or nil
    end
    if child and not blocker then blocker="native material animation JObj sibling chain exceeds audit budget" end
  end
  pair(root,maroot,0)
  if blocker then return nil,#clips,blocker end
  return {byDobj=byDobj,animated=animated,clip=ci,clipCount=#clips},#clips
end

-- Convert the exact SysDolphin texture matrix to the affine two-coordinate
-- form the portable Waza shader can consume. Ordinary UV TObj stages have a
-- constant Q; projected/reflection stages deliberately fail closed here.
local function textureAffine(t)
  local m=sourceTextureMatrix(t)
  if not m or abs(m[9])>1e-10 or abs(m[10])>1e-10 then return nil,"non-affine source texture matrix" end
  local q=m[11]+m[12]
  if abs(q)<1e-10 then return nil,"degenerate source texture matrix" end
  return {m[1]/q,m[2]/q,(m[3]+m[4])/q,m[5]/q,m[6]/q,(m[7]+m[8])/q}
end

local function textureAffineInverse(m)
  if type(m)~="table" then return nil,"source texture affine unavailable" end
  local det=(tonumber(m[1]) or 0)*(tonumber(m[5]) or 0)-(tonumber(m[2]) or 0)*(tonumber(m[4]) or 0)
  if abs(det)<1e-12 then return nil,"singular source texture affine" end
  local a,b,c,d,e,f=m[1],m[2],m[3],m[4],m[5],m[6]
  return {e/det,-b/det,(b*f-e*c)/det,-d/det,a/det,(d*c-a*f)/det}
end
local function textureAnimKeysConstant(keys,value)
  value=tonumber(value) or 0
  for _,k in ipairs(keys or {}) do
    -- HSD_A_OP_SLP (5) only changes the Hermite tangent. A non-zero tangent on
    -- an otherwise constant stream still produces motion between authored keys.
    if k.op~=5 and (not finite(k.value) or abs((tonumber(k.value) or 0)-value)>1e-8) then return false end
    if (k.op==4 or k.op==5) and abs(tonumber(k.tan) or 0)>1e-8 then return false end
  end
  return true
end
local function textureAnimBase(state,baseInverse)
  local s,r,p=state.scale or {1,1,1},state.rotation or {0,0,0},state.translation or {0,0,0}
  return {scale={s[1] or 1,s[2] or 1},rotationZ=r[3] or 0,translation={p[1] or 0,p[2] or 0},
    repeatS=tonumber(state.repeatS) or 1,repeatT=tonumber(state.repeatT) or 1,wrapT=tonumber(state.wrapT) or 0,baseInverse=baseInverse}
end

-- Evaluate the HSD_TexAnim portion of a MatAnimJoint bank without guessing
-- texture behavior. GC6E01 TObjUpdateFunc proves tracks 2/3/4/5/8 are the UV
-- translation/scale/Z-rotation inputs consumed by MakeTextureMtx. Those are
-- exactly representable by the portable two-coordinate shader. Constant
-- zero X/Y rotation and unchanged blend tracks are harmless authored streams;
-- image/TLUT swaps, LOD/TEV animation, non-zero X/Y rotation, or animated blend
-- are rejected so an effect never receives a plausible partial animation.
local function nativeTexturePoseRoot(a,root,clipIndex,frame,sourceStates)
  local clips=nativeMaterialAnimations(a,root)
  local ci=math.max(0,math.floor(tonumber(clipIndex) or 0))
  local maroot=clips[ci+1]
  if not maroot then return nil,#clips,("native texture animation index %d unavailable (%d source clips)"):format(ci,#clips) end
  local byDobj={};local animated=false;local blocker=nil;local seenJ={};local maxEnd=0
  local function noteAObj(aobj)
    if not aobj then return end
    local e=f32(a.blob,aobj+0x04+1)
    if not finite(e) or e<0 then blocker="native HSD_TexAnim AObj end frame invalid";return end
    if e>maxEnd then maxEnd=e end
  end
  local function evalTexture(dobj,ma)
    if blocker then return end
    local mobj=a:ptr(dobj+0x08)
    local supplied=sourceStates and sourceStates[dobj]
    local state,tobj
    if supplied and supplied.state and supplied.tobj then
      local s,r,p=supplied.state.scale or {1,1,1},supplied.state.rotation or {0,0,0},supplied.state.translation or {0,0,0}
      state={coordinateMode=supplied.state.coordinateMode,texgen=supplied.state.texgen,blending=supplied.state.blending,
        wrapT=supplied.state.wrapT,repeatS=supplied.state.repeatS,repeatT=supplied.state.repeatT,
        scale={s[1],s[2],s[3]},rotation={r[1],r[2],r[3]},translation={p[1],p[2],p[3]}}
      tobj=supplied.tobj
    elseif not sourceStates then
      state,tobj=firstEnabledTexture(a,mobj,true)
    end
    if ma then noteAObj(a:ptr(ma+0x04)) end
    local texanim=ma and a:ptr(ma+0x08) or nil
    -- GSmodelSetTexAnimIndex derives one shared tex_anim_end_frame from every
    -- AObj attached by the selected HSD_MatAnimJoint bank. Preserve that clock
    -- even when this portable renderer only displays the first enabled TObj.
    local scan,scanGuard=texanim,0
    while scan and scanGuard<64 and not blocker do
      scanGuard=scanGuard+1;noteAObj(a:ptr(scan+0x08));scan=a:ptr(scan)
    end
    if scan and not blocker then blocker="native HSD_TexAnim chain exceeds audit budget";return end
    if not (state and tobj) then return end
    if not texanim then return end
    local authoredId=u32(a.blob,tobj+0x08+1)
    local ta,guard=texanim,0
    while ta and guard<64 do
      guard=guard+1
      if u32(a.blob,ta+0x04+1)==authoredId then break end
      ta=a:ptr(ta)
    end
    if ta and guard>=64 and u32(a.blob,ta+0x04+1)~=authoredId then blocker="native HSD_TexAnim chain exceeds audit budget";return end
    if not ta then return end -- source has a TexAnim bank, but not for this enabled TObj
    local nImage=u16(a.blob,ta+0x14+1) or 0
    local nTlut=u16(a.blob,ta+0x16+1) or 0
    if a:ptr(ta+0x0C) or nImage~=0 then blocker="native HSD_TexAnim image switching unsupported by Waza renderer";return end
    if a:ptr(ta+0x10) or nTlut~=0 then blocker="native HSD_TexAnim TLUT switching unsupported by Waza renderer";return end
    local aobj=a:ptr(ta+0x08);local fd=aobj and a:ptr(aobj+0x08) or nil;guard=0
    local baseBlend=tonumber(state.blending) or 1
    local baseAffine,baseWhy=textureAffine(state)
    if not baseAffine then blocker=baseWhy;return end
    local baseInverse,invWhy=textureAffineInverse(baseAffine)
    if not baseInverse then blocker=invWhy;return end
    -- Keep the authored static TObj SRT separate from the frame-0 working
    -- state below. Delayed FObj streams intentionally retain this base until
    -- their first key; serializing the mutated frame-0 pose as the base would
    -- make those streams start from the wrong value on later runtime samples.
    local baseState=textureAnimBase(state,baseInverse)
    local tracks={}
    while fd and guard<64 and not blocker do
      guard=guard+1
      local track,keys=decodeFobj(a,fd)
      if type(track)~="number" then blocker="native HSD_TexAnim track id unavailable";break end
      local v=fobjValue(keys,frame or 0)
      if track==2 or track==3 or track==4 or track==5 or track==8 then
        for _,k in ipairs(keys) do
          if not finite(k.frame) or not finite(k.value) or not finite(k.tan) then
            blocker=("native HSD_TexAnim track %d contains non-finite source keys"):format(track);break
          end
        end
        if blocker then break end
        animated=true
        tracks[track]=keys
        if v~=nil then
          if not finite(v) then blocker=("native HSD_TexAnim track %d is non-finite"):format(track);break end
          if track==2 then state.translation[1]=v
          elseif track==3 then state.translation[2]=v
          elseif track==4 then state.scale[1]=v
          elseif track==5 then state.scale[2]=v
          else state.rotation[3]=v end
        end
      elseif track==6 or track==7 then
        -- X/Y texture rotations make Q vary and require projective texture
        -- interpolation. Blizzard authors these as literal zero streams.
        if not textureAnimKeysConstant(keys,0) then blocker=("native HSD_TexAnim track %d requires projective UVs"):format(track);break end
      elseif track==9 then
        if not textureAnimKeysConstant(keys,baseBlend) then blocker="native HSD_TexAnim animated blend unsupported by Waza renderer";break end
      elseif track==1 then
        blocker="native HSD_TexAnim image-index track unsupported by Waza renderer"
      elseif track>=10 and track<=24 then
        blocker=("native HSD_TexAnim track %d unsupported by Waza renderer"):format(track)
      else
        blocker=("native HSD_TexAnim track %d unknown"):format(track)
      end
      fd=a:ptr(fd)
    end
    if fd and not blocker then blocker="native HSD_TexAnim FObj chain exceeds audit budget";return end
    if blocker then return end
    local affine,why=textureAffine(state)
    if not affine then blocker=why;return end
    byDobj[dobj]={affine=affine,sourceTextureId=authoredId,
      animation={revision=1,base=baseState,tracks=tracks}}
  end
  local function pair(j,mj,depth)
    if blocker or not j or seenJ[j] or depth>256 then return end
    seenJ[j]=true
    local dobj=a:ptr(j+0x10);local ma=mj and a:ptr(mj+0x08) or nil;local guard=0
    while dobj and guard<256 and not blocker do
      guard=guard+1;evalTexture(dobj,ma)
      dobj=a:ptr(dobj+0x04);ma=ma and a:ptr(ma) or nil
    end
    if dobj and not blocker then blocker="native texture animation DObj chain exceeds audit budget";return end
    local child=a:ptr(j+0x08);local childMat=mj and a:ptr(mj) or nil;local childGuard=0
    while child and childGuard<256 and not blocker do
      childGuard=childGuard+1;pair(child,childMat,depth+1)
      child=a:ptr(child+0x0C);childMat=childMat and a:ptr(childMat+0x04) or nil
    end
    if child and not blocker then blocker="native texture animation JObj sibling chain exceeds audit budget" end
  end
  pair(root,maroot,0)
  if blocker then return nil,#clips,blocker end
  return {byDobj=byDobj,animated=animated,clip=ci,clipCount=#clips,endFrame=maxEnd},#clips
end

-- Compact arena-specific HSD_MObj animation extraction. GC6E01's MObjUpdateFunc
-- maps tracks 1..9 to ambient/diffuse/specular RGB and track 10 to material
-- alpha (1-value). Arena.lua can reproduce exactly those channels. PE refs /
-- destination alpha (11..13) are not equivalent to the portable arena alpha
-- path, so a DObj carrying them is marked blocked rather than partially played.
-- The shared GSmodel "tex animation" clock covers both MObj and TObj AObjs, so
-- include every attached TexAnim AObj when deriving the authored end frame.
local function nativeArenaMaterialAnimationRoot(a,root,clipIndex)
  local clips=nativeMaterialAnimations(a,root)
  local ci=math.max(0,math.floor(tonumber(clipIndex) or 0))
  local maroot=clips[ci+1]
  if not maroot then return nil,#clips,("native arena material animation index %d unavailable (%d source clips)"):format(ci,#clips) end
  local byDobj={};local maxEnd=0;local fatal=nil;local seenJ={}
  local function noteAObj(aobj)
    if not aobj then return end
    local e=f32(a.blob,aobj+0x04+1)
    if not finite(e) or e<0 then fatal="native arena material AObj end frame invalid";return end
    if e>maxEnd then maxEnd=e end
  end
  local function evalMaterial(dobj,ma)
    if fatal then return end
    local aobj=ma and a:ptr(ma+0x04) or nil;noteAObj(aobj)
    local ta=ma and a:ptr(ma+0x08) or nil;local tg=0
    while ta and tg<64 and not fatal do tg=tg+1;noteAObj(a:ptr(ta+0x08));ta=a:ptr(ta) end
    if ta and not fatal then fatal="native arena material TexAnim chain exceeds audit budget";return end
    if not aobj then byDobj[dobj]={revision=1,state="static"};return end
    local tracks={};local animated=false;local blocked=false;local fd=a:ptr(aobj+0x08);local guard=0
    while fd and guard<64 do
      guard=guard+1
      local track,keys=decodeFobj(a,fd)
      if type(track)~="number" then blocked=true;break end
      if track>=1 and track<=10 then
        for _,k in ipairs(keys) do
          if not finite(k.frame) or not finite(k.value) or not finite(k.tan) then blocked=true;break end
        end
        if blocked then break end
        if #keys>0 then tracks[track]=keys;animated=true end
      elseif track>=11 and track<=13 then
        blocked=true -- PE alpha-test/destination-alpha animation is not portable here.
      else
        blocked=true
      end
      fd=a:ptr(fd)
    end
    if fd then blocked=true end
    if blocked then byDobj[dobj]={revision=1,state="blocked"}
    elseif animated then byDobj[dobj]={revision=1,state="animated",tracks=tracks}
    else byDobj[dobj]={revision=1,state="static"} end
  end
  local function pair(j,mj,depth)
    if fatal or not j or seenJ[j] or depth>256 then return end
    seenJ[j]=true
    local dobj=a:ptr(j+0x10);local ma=mj and a:ptr(mj+0x08) or nil;local guard=0
    while dobj and guard<256 and not fatal do
      guard=guard+1;evalMaterial(dobj,ma);dobj=a:ptr(dobj+0x04);ma=ma and a:ptr(ma) or nil
    end
    if dobj and not fatal then fatal="native arena material DObj chain exceeds audit budget";return end
    local child=a:ptr(j+0x08);local childMat=mj and a:ptr(mj) or nil;local childGuard=0
    while child and childGuard<256 and not fatal do
      childGuard=childGuard+1;pair(child,childMat,depth+1);child=a:ptr(child+0x0C);childMat=childMat and a:ptr(childMat+0x04) or nil
    end
    if child and not fatal then fatal="native arena material JObj sibling chain exceeds audit budget" end
  end
  pair(root,maroot,0)
  if fatal then return nil,#clips,fatal end
  return {byDobj=byDobj,clip=ci,clipCount=#clips,endFrame=maxEnd},#clips
end

local function plausibleJobj(a,p)
  if not p or p<a.data or p+0x3F>=a.data+a.dataSize then return false end
  local b=a.blob;local flags=u32(b,p+0x04+1) or 0
  local sx,sy,sz=f32(b,p+0x20+1),f32(b,p+0x24+1),f32(b,p+0x28+1)
  local tx,ty,tz=f32(b,p+0x2C+1),f32(b,p+0x30+1),f32(b,p+0x34+1)
  -- Bit 31 appears in older SysDolphin/HSD tooling as a legacy JOBJ/shadow
  -- marker. Do not reject an otherwise coherent joint solely because it is set.
  return finite(sx) and finite(sy) and finite(sz) and finite(tx) and finite(ty) and finite(tz)
    and abs(sx)<10000 and abs(sy)<10000 and abs(sz)<10000
    and abs(tx)<1e8 and abs(ty)<1e8 and abs(tz)<1e8
end
-- Return only the authoritative HSD_SceneModelSet roots advertised by
-- scene_data. Character PKX files already tell us exactly which JOBJ root(s)
-- belong to the model; relocation-derived "plausible" roots are only a recovery
-- heuristic for malformed/legacy assets and can decode arbitrary data blocks as
-- extra geometry. Pokemon extraction opts into this semantic-only path.
local function semanticModelRoots(a,maxRoots)
  maxRoots=tonumber(maxRoots) or 192
  local roots,seen={},{}
  local scene=a:publicSymbol("scene_data")
  local sets=scene and a:ptr(scene) or nil
  if not sets then return roots end
  for i=0,maxRoots-1 do
    local modelSet=a:ptr(sets+i*4)
    if not modelSet then break end
    local root=a:ptr(modelSet)
    if root and plausibleJobj(a,root) and not seen[root] then
      seen[root]=true
      roots[#roots+1]=root
    end
  end
  return roots
end

local function candidateRoots(a,maxRoots)
  maxRoots=tonumber(maxRoots) or 192
  local raw,rawSeen,roots,rootSeen={}, {},{},{}
  local function full()return #roots>=maxRoots end
  local function addRaw(p)if p and not rawSeen[p] then rawSeen[p]=true;raw[#raw+1]=p end end
  local function addRoot(p)
    if not full() and plausibleJobj(a,p) and not rootSeen[p] then rootSeen[p]=true;roots[#roots+1]=p end
  end
  local scene=a:publicSymbol("scene_data")
  if scene then
    addRaw(scene)
    -- SysDolphin HSD_SceneDesc.modelsets is NOT an inline/contiguous run of
    -- HSD_SceneModelSet structs. It is a NULL-terminated array of pointers to
    -- model-set structs. Each model-set's first field is the root JOBJ pointer.
    --
    -- The old contiguous interpretation could fill maxRoots with plausible
    -- garbage before this real pointer-array path ran. Character DATs then
    -- reported dozens of candidate roots while never testing their actual
    -- skeleton. Keep the semantic scene roots first and authoritative.
    local sets=a:ptr(scene)
    if sets then
      for i=0,127 do
        if full() then break end
        local modelSet=a:ptr(sets+i*4)
        if not modelSet then break end
        addRoot(a:ptr(modelSet)) -- HSD_SceneModelSet.joint
      end
    end
    -- Keep secondary scene pointers available only as later fallbacks.
    for off=4,0x0C,4 do addRaw(a:ptr(scene+off)) end
  end
  -- Preserve semantic/public roots ahead of relocation-derived guesses.
  for _,sym in ipairs(a:publicSymbols()) do addRaw(sym.ptr);addRoot(sym.ptr);if full() then break end end
  for _,p in ipairs(raw) do
    if full() then break end
    addRoot(p);for off=0,0x40,4 do if full() then break end;addRoot(a:ptr(p+off)) end
  end
  -- Relocations are a fallback pool. Cap them: malformed/complex files can
  -- expose thousands of plausible float blocks that are not JOBJ roots.
  if not full() then
    local relocLimit=math.min(a.relocCount,20000)
    for i=0,relocLimit-1 do
      local fieldOff=u32(a.blob,a.reloc+i*4+1)
      if fieldOff and fieldOff<a.dataSize then addRoot(a:ptr(a.data+fieldOff)) end
      if full() then break end
    end
  end
  return roots
end

-- Source-equivalent Waza owner bound for one exact HSD animation index at
-- frame 0. This mirrors the GSmodelParse(..., trsp_mask=7, is_visible=TRUE)
-- geometry walk used by fn_800EB268 rather than deriving a box from CBE's
-- normalized visible mesh. Unsupported runtime transform classes are explicit
-- blockers: a partial-but-plausible AABB is worse than no exact bound because
-- Waza uses it for both owner-centre transforms and FOV endpoints.
local function extractRetailBoundRoot(a,root,animationIndex,opts)
  opts=opts or {}
  animationIndex=tonumber(animationIndex)
  if animationIndex==nil or animationIndex<0 or animationIndex~=floor(animationIndex) then
    return nil,"retail-bound exact animation index required"
  end
  local pose,clipCount,poseBlocker=nativeRetailBoundPose(a,root,animationIndex)
  if not pose then
    if poseBlocker then return nil,poseBlocker end
    return nil,("retail-bound animation index %d unavailable (%d source clips)"):format(animationIndex,clipCount or 0)
  end

  local worldByJobj,parentByJobj,flagsByJobj,inverseBindByJobj,scaleByJobj={},{},{},{},{}
  local mapSeen={}
  local blocker=nil
  local function jobjSRT(j)
    local v=pose[j]
    if v then return v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8],v[9],v.classicalScale end
    local b=a.blob
    local flags=u32(b,j+0x04+1) or 0
    return f32(b,j+0x14+1) or 0,f32(b,j+0x18+1) or 0,f32(b,j+0x1C+1) or 0,
      f32(b,j+0x20+1) or 1,f32(b,j+0x24+1) or 1,f32(b,j+0x28+1) or 1,
      f32(b,j+0x2C+1) or 0,f32(b,j+0x30+1) or 0,f32(b,j+0x34+1) or 0,hasFlag(flags,0x8)
  end
  local function unsupportedTransform(flags,j)
    if hasFlag(flags,0x1000) then return "retail-bound JObj instance transform unsupported" end
    if hasFlag(flags,0x20000) then return "retail-bound quaternion JObj transform unsupported" end
    if hasFlag(flags,0x800000) then return "retail-bound user-defined JObj matrix unsupported" end
    if hasFlag(flags,0x1000000) then return "retail-bound independent-parent JObj matrix unsupported" end
    if hasFlag(flags,0x2000000) then return "retail-bound independent-SRT JObj matrix unsupported" end
    if floor(flags/0x200000)%4~=0 then return "retail-bound IK JObj transform unsupported" end
    if a:ptr(j+0x3C) then return "retail-bound constrained RObj transform unsupported" end
  end
  local function mapWorld(j,parent,parentJobj,depth)
    if blocker or not j or mapSeen[j] or depth>256 then return end
    if not plausibleJobj(a,j) then blocker="retail-bound invalid JObj descriptor";return end
    mapSeen[j]=true
    local flags=u32(a.blob,j+0x04+1) or 0
    flagsByJobj[j]=flags;parentByJobj[j]=parentJobj
    blocker=unsupportedTransform(flags,j) or blocker
    if blocker then return end
    local ibp=a:ptr(j+0x38);if ibp then inverseBindByJobj[j]=hsdMatrix4x3(a,ibp) end
    local rx,ry,rz,sx,sy,sz,tx,ty,tz,classical=jobjSRT(j)
    if not (finite(rx) and finite(ry) and finite(rz) and finite(sx) and finite(sy) and finite(sz)
        and finite(tx) and finite(ty) and finite(tz)) then blocker="retail-bound invalid JObj frame-0 SRT";return end
    local parentScale=parentJobj and scaleByJobj[parentJobj] or nil
    scaleByJobj[j]=inheritedScale(parentScale,sx,sy,sz,classical)
    worldByJobj[j]=mul(parent,localM(rx,ry,rz,sx,sy,sz,tx,ty,tz,parentScale))
    mapWorld(a:ptr(j+0x08),worldByJobj[j],j,depth+1)
    mapWorld(a:ptr(j+0x0C),parent,parentJobj,depth+1)
  end
  mapWorld(root,ident(),nil,0)
  if blocker then return nil,blocker end

  local budget={
    checkpoint=opts.checkpoint,displayOps=0,vertices=0,maxDisplayOps=opts.maxDisplayOps or 600000,
    maxVertices=opts.maxVertices or 200000,maxCommands=opts.maxCommands or 8192,
    jobjs=0,dobjs=0,pobjs=0,min={1e30,1e30,1e30},max={-1e30,-1e30,-1e30},
    worldByJobj=worldByJobj,parentByJobj=parentByJobj,flagsByJobj=flagsByJobj,
    inverseBindByJobj=inverseBindByJobj,inverseBindResolved={},envelopeCoordCache={},
    envelopeWorldCache={},retailEnvelopePalettes={},skinFix=true,
  }
  local maxJobjs=opts.maxJobjs or 8192
  local maxDobjs=opts.maxDobjs or 24576
  local maxPobjs=opts.maxPobjs or 49152
  local seen={}
  local function walk(j,depth)
    if budget.exhausted or not j or seen[j] or depth>256 then return end
    if not plausibleJobj(a,j) then budget.exhausted="retail-bound invalid traversal JObj";return end
    seen[j]=true
    budget.jobjs=budget.jobjs+1
    if budget.jobjs>maxJobjs then budget.exhausted="retail-bound JObj traversal budget";return end
    local flags=flagsByJobj[j] or (u32(a.blob,j+0x04+1) or 0)
    if hasFlag(flags,0x1000) then budget.exhausted="retail-bound JObj instance transform unsupported";return end
    local isHidden=hasFlag(flags,0x10)
    local isParticle=hasFlag(flags,0x20)
    local isSpline=hasFlag(flags,0x4000)
    local hasGeometryPass=hasFlag(flags,0x00040000) or hasFlag(flags,0x00080000) or hasFlag(flags,0x00100000)
    if hasGeometryPass and not isHidden and not isParticle and not isSpline then
      if flags%0x1000>=0x200 then
        budget.exhausted="retail-bound billboard position matrix unsupported";return
      end
      local dobj=a:ptr(j+0x10)
      local localD=0
      while dobj and localD<256 and not budget.exhausted do
        localD=localD+1;budget.dobjs=budget.dobjs+1
        if budget.dobjs>maxDobjs then budget.exhausted="retail-bound DObj traversal budget";break end
        local mobj=a:ptr(dobj+0x08)
        local pobj=a:ptr(dobj+0x0C)
        local renderFlags=mobj and (u32(a.blob,mobj+0x04+1) or 0) or nil
        local passFlag,passName=nil,nil
        if renderFlags then passFlag,passName=retailDobjPassFlag(renderFlags) end
        if renderFlags and not passFlag then budget.exhausted=passName or "retail-bound DObj pass unavailable";break end
        local passOK=passFlag and retailJobjHasPass(flags,passFlag) or false
        if passOK then
          if passName=="opa" then budget.opaDobjs=(budget.opaDobjs or 0)+1
          elseif passName=="xlu" then budget.xluDobjs=(budget.xluDobjs or 0)+1
          elseif passName=="texedge" then budget.texedgeDobjs=(budget.texedgeDobjs or 0)+1 end
          if renderFlags and hasFlag(renderFlags,0x04000000) then budget.shadowDobjs=(budget.shadowDobjs or 0)+1 end
          local localP=0
          while pobj and localP<1024 and not budget.exhausted do
            localP=localP+1;budget.pobjs=budget.pobjs+1
            if budget.pobjs>maxPobjs then budget.exhausted="retail-bound PObj traversal budget";break end
            retailBoundDisplay(a,pobj,worldByJobj[j],budget,j)
            pobj=a:ptr(pobj+0x04)
          end
        else
          budget.nonRenderDobjs=(budget.nonRenderDobjs or 0)+1
        end
        dobj=a:ptr(dobj+0x04)
      end
    elseif isHidden then budget.hiddenJobjs=(budget.hiddenJobjs or 0)+1 end

    -- _modelParseJObjDispAll descends only when the current JObj advertises a
    -- ROOT OPA/XLU/TEXEDGE pass. Child siblings are then visited individually.
    if hasFlag(flags,0x10000000) or hasFlag(flags,0x20000000) or hasFlag(flags,0x40000000) then
      local child=a:ptr(j+0x08);local guard=0
      while child and guard<1024 and not budget.exhausted do
        guard=guard+1;walk(child,depth+1);child=a:ptr(child+0x0C)
      end
      if guard>=1024 then budget.exhausted="retail-bound child traversal budget" end
    end
  end
  walk(root,0)
  if budget.exhausted then return nil,budget.exhausted,budget end
  if budget.vertices<=0 then return nil,"retail-bound no submitted source positions",budget end
  local mn,mx=budget.min,budget.max
  local extent={mx[1]-mn[1],mx[2]-mn[2],mx[3]-mn[3]}
  local center={(mn[1]+mx[1])*.5,(mn[2]+mx[2])*.5,(mn[3]+mx[3])*.5}
  return {
    min={mn[1],mn[2],mn[3]},max={mx[1],mx[2],mx[3]},extent=extent,center=center,
    animationIndex=animationIndex,frame=0,exact=true,format="gc6e01-gsmodel-bound-v1",
    stats={vertices=budget.vertices,jobjs=budget.jobjs,dobjs=budget.dobjs,pobjs=budget.pobjs,
      skippedPobj800=budget.skippedPobj800 or 0,shapePobjs=budget.shapePobjs or 0,
      envelopePobjs=budget.envelopePobjs or 0,shadowDobjs=budget.shadowDobjs or 0,
      opaDobjs=budget.opaDobjs or 0,xluDobjs=budget.xluDobjs or 0,texedgeDobjs=budget.texedgeDobjs or 0,
      nonRenderDobjs=budget.nonRenderDobjs or 0,envelopeBlends=budget.envelopeBlends or 0,
      inverseBindMissing=budget.inverseBindMissing or 0,retailEnvelopePalettes=budget.retailEnvelopePaletteCount or 0,
      retailEnvelopeMulti=budget.retailEnvelopeMulti or 0},
  },nil,budget
end

local function extractRoot(a,root,opts)
  opts=opts or {}
  if opts.checkpoint then opts.checkpoint("Decoding source geometry") end
  local groups={};local seen={};local min={1e30,1e30,1e30};local max={-1e30,-1e30,-1e30};local vertices=0
  local pose,clipCount=nil,0
  if opts.nativePose then pose,clipCount=nativePose(a,root,tonumber(opts.nativePose.clip) or 0,tonumber(opts.nativePose.frame) or 0) end
  local worldByJobj={};local mapSeen={};local jointWorlds={};local jointIndexByJobj={};local jointParents={}
  local parentByJobj={};local flagsByJobj={};local inverseBindByJobj={};local scaleByJobj={}
  local function jobjSRT(j)
    local v=pose and pose[j]
    if v then return v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8],v[9] end
    local b=a.blob;return f32(b,j+0x14+1) or 0,f32(b,j+0x18+1) or 0,f32(b,j+0x1C+1) or 0,
      f32(b,j+0x20+1) or 1,f32(b,j+0x24+1) or 1,f32(b,j+0x28+1) or 1,
      f32(b,j+0x2C+1) or 0,f32(b,j+0x30+1) or 0,f32(b,j+0x34+1) or 0
  end
  local function mapWorld(j,parent,parentJobj,depth)
    if not j or mapSeen[j] or depth>256 or not plausibleJobj(a,j) then return end
    if opts.checkpoint then opts.checkpoint() end
    mapSeen[j]=true
    parentByJobj[j]=parentJobj
    flagsByJobj[j]=u32(a.blob,j+0x04+1) or 0
    local ibp=a:ptr(j+0x38);if ibp then inverseBindByJobj[j]=hsdMatrix4x3(a,ibp) end
    -- PNMTXIDX is resolved inside each enveloped POBJ's own matrix palette; it
    -- is deliberately NOT interpreted as an index into this JOBJ traversal.
    local rx,ry,rz,sx,sy,sz,tx,ty,tz=jobjSRT(j)
    local parentScale=opts.nativeScaleCompensation and parentJobj and scaleByJobj[parentJobj] or nil
    local classical=hasFlag(flagsByJobj[j],0x8)
    if pose and pose[j] then classical=pose[j].classicalScale end
    if opts.nativeScaleCompensation then scaleByJobj[j]=inheritedScale(parentScale,sx,sy,sz,classical) end
    local world=mul(parent,localM(rx,ry,rz,sx,sy,sz,tx,ty,tz,parentScale));worldByJobj[j]=world
    -- ModelSequence/PKX body-map indices address the model's ordered JOBJ
    -- array. HSD builds that order with the same child-before-sibling DFS used
    -- here. Preserve the full source joint origin table so battle particles can
    -- attach to Mouth/Chest/Tail/Hands instead of a percentage of model height.
    local ji=#jointWorlds
    jointIndexByJobj[j]=ji
    jointWorlds[ji+1]={world[4] or 0,world[8] or 0,world[12] or 0}
    -- Preserve the source skeleton topology as 1-based parent indices.  This
    -- lets trainer/capture code select a real arm end-effector instead of
    -- guessing "hand" from height alone (which rejects a lowered throwing
    -- wrist and can incorrectly attach the ball to an elbow/shoulder).
    local parentIndex=parentJobj and jointIndexByJobj[parentJobj] or nil
    jointParents[ji+1]=parentIndex and (parentIndex+1) or 0
    -- An INSTANCE child is a reference to an already loaded joint, not a
    -- transform child. Mapping it under this owner corrupts the shared bank's
    -- rest matrix and makes subsequent instances inherit the first placement.
    if not (opts.nativeSceneInstances and hasFlag(flagsByJobj[j],0x1000)) then mapWorld(a:ptr(j+0x08),world,j,depth+1) end
    mapWorld(a:ptr(j+0x0C),parent,parentJobj,depth+1)
  end
  mapWorld(root,ident(),nil,0)
  -- Trainer legs use authored two-bone IK chains. Ordinary SRT evaluation
  -- leaves their ankles under the unsolved knee transform, tilting the feet.
  -- Resolve only the explicit source JOINT1/JOINT2/EFFECTOR + IKHINT contract.
  local ikDiagnostics=opts.nativeIKDiagnostics and {} or nil
  if opts.nativeTrainerIK then
    local function sub(x,y)return {x[1]-y[1],x[2]-y[2],x[3]-y[3]} end
    local function dot(x,y)return x[1]*y[1]+x[2]*y[2]+x[3]*y[3] end
    local function cross(x,y)return {x[2]*y[3]-x[3]*y[2],x[3]*y[1]-x[1]*y[3],x[1]*y[2]-x[2]*y[1]} end
    local function unit(x)local d=sqrt(dot(x,x));if d<1e-8 then return nil end;return {x[1]/d,x[2]/d,x[3]/d},d end
    local function pos(m)return {m[4],m[8],m[12]} end
    local function constraint(j,kind,subtype)
      local r=a:ptr(j+0x3c);local guard=0
      while r and guard<64 do
        local f=u32(a.blob,r+4+1) or 0
        if hasFlag(f,0x80000000) and floor(f/0x10000000)%8==kind and (not subtype or f%0x10000000==subtype) then return a:ptr(r+8),f end
        r=a:ptr(r);guard=guard+1
      end
    end
    local function basis(x,z,origin,sc)
      local y=unit(cross(z,x));if not y then return nil end
      z=unit(cross(x,y));sc=sc or {1,1,1}
      return {x[1]*sc[1],y[1]*sc[2],z[1]*sc[3],origin[1],x[2]*sc[1],y[2]*sc[2],z[2]*sc[3],origin[2],x[3]*sc[1],y[3]*sc[2],z[3]*sc[3],origin[3],0,0,0,1}
    end
    local function childWorld(j,parent)
      local rx,ry,rz,sx,sy,sz,tx,ty,tz=jobjSRT(j)
      return mul(parent,localM(rx,ry,rz,sx,sy,sz,tx,ty,tz,opts.nativeScaleCompensation and scaleByJobj[parentByJobj[j]] or nil))
    end
    for upper,flags in pairs(flagsByJobj) do
      if floor(flags/0x200000)%4==1 then
        local lower=a:ptr(upper+8);local eff=lower and a:ptr(lower+8)
        local h1=constraint(upper,4);local h2,flip=lower and constraint(lower,4)
        -- Lua's logical operators discard extra return values.
        if lower then h2,flip=constraint(lower,4) end
        local target=eff and constraint(eff,1,1)
        local parent=parentByJobj[upper]
        if h1 and h2 and target and worldByJobj[target] and parent and worldByJobj[parent]
          and floor((flagsByJobj[lower] or 0)/0x200000)%4==2 and floor((flagsByJobj[eff] or 0)/0x200000)%4==3 then
          local hip=pos(worldByJobj[parent]);local goal=pos(worldByJobj[target]);local delta=sub(goal,hip)
          local dir,d=unit(delta);local sc1=scaleByJobj[upper] or {1,1,1};local sc2=scaleByJobj[lower] or sc1
          local l1=(f32(a.blob,h1+1) or 0)*sc1[1];local l2=(f32(a.blob,h2+1) or 0)*sc2[1]
          local old=worldByJobj[upper];local z={old[3],old[7],old[11]}
          local bend=dir and unit(cross(z,dir))
          if dir and bend and l1>1e-6 and l2>1e-6 then
            z=unit(cross(dir,bend))
            local along=(d*d+l1*l1-l2*l2)/(2*d)
            along=math.max(-l1,math.min(l1,along))
            local height=sqrt(math.max(0,l1*l1-along*along))*(hasFlag(flip or 0,4) and -1 or 1)
            local knee={hip[1]+dir[1]*along+bend[1]*height,hip[2]+dir[2]*along+bend[2]*height,hip[3]+dir[3]*along+bend[3]*height}
            local x1=unit(sub(knee,hip));local x2=unit(sub(goal,knee))
            if x1 and x2 then
              worldByJobj[upper]=basis(x1,z,hip,sc1);worldByJobj[lower]=basis(x2,z,knee,sc2)
              local ew=childWorld(eff,worldByJobj[lower])
              ew[4]=knee[1]+x2[1]*l2;ew[8]=knee[2]+x2[2]*l2;ew[12]=knee[3]+x2[3]*l2;worldByJobj[eff]=ew
              local visited={}
              local function descend(j,p,depth)
                if not j or visited[j] or depth>256 then return end;visited[j]=true
                if j~=lower and j~=eff then worldByJobj[j]=childWorld(j,p) end
                descend(a:ptr(j+8),worldByJobj[j],depth+1);descend(a:ptr(j+12),p,depth+1)
              end
              -- Feet may be siblings of the effector under the lower bone.
              -- Rebuild the whole changed subtree, preserving solved matrices.
              descend(a:ptr(upper+8),worldByJobj[upper],0)
              if ikDiagnostics then
                ikDiagnostics[#ikDiagnostics+1]={upper=jointIndexByJobj[upper]+1,
                  lower=jointIndexByJobj[lower]+1,effector=jointIndexByJobj[eff]+1,
                  target=jointIndexByJobj[target]+1,length1=l1,length2=l2}
              end
            end
          end
        end
      end
    end
    for j,index in pairs(jointIndexByJobj) do jointWorlds[index+1]=pos(worldByJobj[j]) end
  end

  local budget={checkpoint=opts.checkpoint,preserveVertexColors=opts.preserveVertexColors==true,displayOps=0,vertices=0,maxDisplayOps=opts.maxDisplayOps or 80000,maxVertices=opts.maxVertices or 30000,jobjs=0,dobjs=0,pobjs=0,shapeIndexMap=opts.shapeIndexMap~=false,worldByJobj=worldByJobj,parentByJobj=parentByJobj,flagsByJobj=flagsByJobj,inverseBindByJobj=inverseBindByJobj,inverseBindResolved={},envelopeCoordCache={},envelopeWorldCache={},skinFix=opts.skinFix~=false,honorRenderPass=opts.honorRenderPass==true,skipShadowMaterials=opts.skipShadowMaterials==true,filterPlaceholders=opts.filterPlaceholders==true}
  local maxJobjs=opts.maxJobjs or 1024;local maxDobjs=opts.maxDobjs or 4096;local maxPobjs=opts.maxPobjs or 8192
  -- Keep joint-world diagnostics because they are useful for detecting a truly
  -- degenerate source transform. Enveloped vertices are placed by their palette
  -- matrices below; this statistic is diagnostic only and never substitutes for
  -- HSD skinning semantics.
  local jointSeen={};local jointStats={}
  local function noteJointWorld(j,world)
    if jointSeen[j] then return end
    jointSeen[j]=true
    local scale,trans=worldScaleTrans(world)
    jointStats[#jointStats+1]={jobj=j,scale=scale,trans=trans}
  end
  local activeInstances={}
  local function walk(j,parent,depth,instanceMatrix,singleRoot)
    if budget.exhausted or not j or (not instanceMatrix and seen[j]) or activeInstances[j] or depth>256 or not plausibleJobj(a,j) then return end
    budget.jobjs=budget.jobjs+1;if budget.jobjs>maxJobjs then budget.exhausted="JOBJ traversal budget";return end
    if not instanceMatrix then seen[j]=true end
    activeInstances[j]=true
    local b=a.blob;local rx,ry,rz,sx,sy,sz,tx,ty,tz=jobjSRT(j)
    local world=worldByJobj[j]
    local flags=u32(b,j+0x04+1) or 0
    if opts.nativeSceneInstances and hasFlag(flags,0x1000) then
      -- HSD_JObjDispAll uses instance.world * inverse(target.world), then
      -- submits ONLY the referenced subtree. It must neither traverse the
      -- target's next sibling nor deduplicate other placements of this bank.
      local target=a:ptr(j+8)
      if not hasFlag(flags,0x10) and target then
        local targetWorld=worldByJobj[target]
        if not targetWorld then budget.exhausted="unresolved scene instance target" else
          local delta=mul(world,invertAffine(targetWorld))
          budget.sceneInstances=(budget.sceneInstances or 0)+1
          walk(target,world,depth+1,delta,true)
        end
      end
      if not singleRoot then walk(a:ptr(j+12),parent,depth+1,instanceMatrix) end
      activeInstances[j]=nil
      return
    end
    -- SysDolphin HSD_JObj visibility/type bits. Pokemon extraction honors both
    -- explicit HIDDEN and the native OPA/XLU/TEXEDGE render-pass membership;
    -- zero-pass helper geometry must never become an ordinary CBE mesh.
    local isSpline=hasFlag(flags,0x00004000)       -- JOBJ_SPLINE
    local isParticle=hasFlag(flags,0x00000020)     -- JOBJ_PTCL
    local isHidden=hasFlag(flags,0x00000010)       -- JOBJ_HIDDEN
    -- Native Colosseum renders JOBJ geometry only when it participates in at
    -- least one OPA/XLU/TEXEDGE pass. Earlier CBE drew zero-pass helper/proxy
    -- geometry as ordinary white meshes; this is the source-faithful filter for
    -- that class of junk and replaces the 1.5.20 spatial guess.
    local noRenderPass=not (hasFlag(flags,0x00040000) or hasFlag(flags,0x00080000) or hasFlag(flags,0x00100000))
    if isHidden then budget.hiddenJobjs=(budget.hiddenJobjs or 0)+1 end
    if budget.honorRenderPass and noRenderPass then budget.nonRenderJobjs=(budget.nonRenderJobjs or 0)+1 end
    -- JOBJ_USE_QUATERNION (1<<17): when set, the three "rotation" floats are
    -- quaternion components, not Euler angles. Reading them as Euler yields
    -- wrong orientations. Counted here so the diagnostic can say whether any
    -- joint in a given model actually uses it.
    if flags%0x40000>=0x20000 then budget.quatJobjs=(budget.quatJobjs or 0)+1 end
    local skipJobjGeometry=isSpline or isParticle or isHidden or (budget.honorRenderPass and noRenderPass)
    local dobj=nil
    if not skipJobjGeometry then dobj=a:ptr(j+0x10) end
    local localD=0
    while dobj and localD<256 and not budget.exhausted do
      localD=localD+1;budget.dobjs=budget.dobjs+1;if budget.dobjs>maxDobjs then budget.exhausted="DOBJ traversal budget";break end
      local mobj=a:ptr(dobj+0x08);local pobj=a:ptr(dobj+0x0C)
      local tex,sourceTobj,texLoaded=nil,nil,false
      local mat=materialInfo(a,mobj);local localP=0

      -- Native HSD dispatches at DOBJ granularity, not merely JOBJ granularity:
      -- opaque materials render only through an OPA owner, while XLU materials
      -- require XLU/TEXEDGE. 1.5.24 treated "owner has ANY render pass" as
      -- permission to draw every DOBJ hanging from it, which can surface
      -- auxiliary material chains the game never submits in that pass.
      local dobjPassOK=true
      if budget.honorRenderPass and mat then
        if mat.xlu then
          dobjPassOK=hasFlag(flags,0x00080000) or hasFlag(flags,0x00100000)
        else
          dobjPassOK=hasFlag(flags,0x00040000)
        end
        if not dobjPassOK then budget.nonRenderDobjs=(budget.nonRenderDobjs or 0)+1 end
      end

      -- RENDER_SHADOW is a dedicated source shadow pass, not body-surface
      -- geometry. CBE already owns arena-side grounding/shadows, and drawing the
      -- caster/pass mesh as an ordinary diffuse mesh is exactly how a white
      -- box/plate can appear around an otherwise recognizable Pokemon.
      local shadowPass=mat and mat.shadow and budget.skipShadowMaterials
      if shadowPass then budget.shadowDobjs=(budget.shadowDobjs or 0)+1 end
      if not dobjPassOK or shadowPass then pobj=nil end

      while pobj and localP<1024 and not budget.exhausted do
        localP=localP+1;budget.pobjs=budget.pobjs+1;if budget.pobjs>maxPobjs then budget.exhausted="POBJ traversal budget";break end
        local rows=parseDisplay(a,pobj,world,budget,j)
        if #rows>0 then
          if instanceMatrix then
            for _,v in ipairs(rows) do
              v[1],v[2],v[3]=point(instanceMatrix,v[1],v[2],v[3])
              local k=#v>=12 and 10 or 6
              v[k],v[k+1],v[k+2]=normal(instanceMatrix,v[k],v[k+1],v[k+2])
            end
          end
          local accept=true
          if type(opts.groupFilter)=="function" then
            local okFilter,result=pcall(opts.groupFilter,rows,mat)
            accept=okFilter and result~=false
          end
          if accept then
            -- Decode each DOBJ's source texture only if at least one polygon
            -- survives the arena envelope. This avoids spending most of a
            -- first-run cache build decoding distant sky/tower effect atlases
            -- that CBE will never render.
            if not texLoaded then
              tex=nil
              if opts.textures~=false then tex,sourceTobj=firstEnabledTexture(a,mobj,opts.sourceTextureState==true or opts.sourceTextureAnimation==true,opts.sourceTextureMetadataOnly==true) end
              texLoaded=true
            end
            applySourceTextureState(rows,tex,opts.sourceTextureState==true)
            for _,v in ipairs(rows) do for k=1,3 do if v[k]<min[k] then min[k]=v[k] end;if v[k]>max[k] then max[k]=v[k] end end end
            vertices=vertices+#rows;budget.vertices=vertices
            noteJointWorld(j,world)
            groups[#groups+1]={vertices=rows,texture=tex,sourceDobj=(opts.sourceMaterialAnimation==true or opts.sourceTextureAnimation==true) and dobj or nil,
              sourceTobj=opts.sourceTextureAnimation==true and sourceTobj or nil,
              alpha=mat and mat.alpha or 1,xlu=mat and mat.xlu or false,noz=mat and mat.noz or false,
              diffuse=mat and mat.diffuse or nil,ambient=mat and mat.ambient or nil,
              specular=mat and mat.specular or nil,shininess=mat and mat.shininess or nil,
              pe=mat and mat.pe or nil,
              renderFlags=mat and mat.renderFlags or 0,shadow=mat and mat.shadow or false,
              effect=mat and mat.effect or false,useConstant=mat and mat.useConstant or false,
              useVertexColor=mat and mat.useVertexColor or false,
              useDiffuseLighting=mat and mat.useDiffuseLighting or false,
              textureSlot=tex and tex.slot or -1}
          end
        end
        pobj=a:ptr(pobj+0x04)
      end
      dobj=a:ptr(dobj+0x04)
    end
    walk(a:ptr(j+0x08),world,depth+1,instanceMatrix)
    if not singleRoot then walk(a:ptr(j+0x0C),parent,depth+1,instanceMatrix) end
    activeInstances[j]=nil
  end
  walk(root,ident(),0)
  local jointScaleMin,jointScaleMax,jointScaleMedian,jointOutliers=nil,nil,nil,0
  if #jointStats>0 then
    local sorted={}
    for i,js in ipairs(jointStats) do sorted[i]=js.scale end
    table.sort(sorted)
    jointScaleMin,jointScaleMax=sorted[1],sorted[#sorted]
    jointScaleMedian=sorted[math.ceil(#sorted/2)]
    for _,s in ipairs(sorted) do
      if jointScaleMedian>1e-6 and (s<jointScaleMedian*0.1 or s>jointScaleMedian*10) then jointOutliers=jointOutliers+1 end
    end
  end
  local filteredGroups,removedGroups=groups,{}
  if budget.filterPlaceholders then filteredGroups,removedGroups=filterPlaceholderGroups(groups) end
  local placeholderVerts=0
  for _,r in ipairs(removedGroups) do placeholderVerts=placeholderVerts+r.vertices end
  local stats={vertices=vertices,shapePobjs=budget.shapePobjs or 0,envelopePobjs=budget.envelopePobjs or 0,displayOps=budget.displayOps or 0,jobjs=budget.jobjs or 0,pobjs=budget.pobjs or 0,nativeClipCount=clipCount,nativePoseApplied=pose~=nil,envelopeBlends=budget.envelopeBlends or 0,
    envelopeBlendsMulti=budget.envelopeBlendsMulti or 0,skinFix=budget.skinFix,
    hiddenJobjs=budget.hiddenJobjs or 0,quatJobjs=budget.quatJobjs or 0,
    jointCount=#jointStats,jointScaleMin=jointScaleMin,jointScaleMedian=jointScaleMedian,jointScaleMax=jointScaleMax,jointScaleOutliers=jointOutliers,
    envelopeCoordEntries=budget.envelopeCoordEntries or 0,singleEnvelopeCoord=budget.singleEnvelopeCoord or 0,singleEnvelopeNoCoord=budget.singleEnvelopeNoCoord or 0,inverseBindMissing=budget.inverseBindMissing or 0,
    honorRenderPass=budget.honorRenderPass,nonRenderJobjs=budget.nonRenderJobjs or 0,
    nonRenderDobjs=budget.nonRenderDobjs or 0,shadowDobjs=budget.shadowDobjs or 0,
    placeholderGroupsRemoved=#removedGroups,placeholderVertsRemoved=placeholderVerts,sceneInstances=budget.sceneInstances or 0}
  if budget.exhausted then return nil,budget.exhausted,stats end
  -- Retail Waza Type-2 resources can be genuine GSmodel/null carriers with no
  -- drawable POBJs at all. Accept that class only when the caller explicitly
  -- opts in, the root came from the archive's semantic model-set table, joints
  -- were actually traversed, and the source contains ZERO polygon objects. A
  -- broken/unsupported mesh still has POBJs and therefore cannot be relabelled
  -- as a successful invisible carrier. Joint matrices are serialized only when
  -- the caller needs attachment tracks; they are not required merely to prove
  -- that the source object is a valid transform-only GSmodel.
  local transformOnly=opts.semanticRootsOnly==true and opts.allowTransformOnly==true
    and vertices==0 and #filteredGroups==0 and #jointWorlds>0 and (budget.jobjs or 0)>0 and (budget.pobjs or 0)==0
  if vertices<math.max(3,tonumber(opts.minVertices) or 60) and not transformOnly then return nil,"too few renderable vertices",stats end
  if transformOnly then min={0,0,0};max={0,0,0} end
  -- Bounds cover source-visible geometry accepted by the decoder. The optional
  -- legacy spatial placeholder filter (normally OFF) runs after these numbers.
  local jointMatrices
  if opts.preserveJointMatrices then
    jointMatrices={}
    for j,index in pairs(jointIndexByJobj) do
      local m=worldByJobj[j];local copy={}
      for k=1,12 do copy[k]=m[k] end
      jointMatrices[index+1]=copy
    end
  end
  return {transformOnly=transformOnly,nativeIK=ikDiagnostics,groups=filteredGroups,vertexCount=vertices,jointPositions=jointWorlds,jointParents=jointParents,jointMatrices=jointMatrices,
    bounds={min=min,max=max,center={(min[1]+max[1])/2,(min[2]+max[2])/2,(min[3]+max[3])/2}}},nil,stats
end

local function archiveDiag(a)
  local names={};for _,s in ipairs(a:publicSymbols()) do if s.name and s.name~="" then names[#names+1]=s.name end end
  local roots=candidateRoots(a,128)
  return {base=a.base,fileSize=a.fileSize,dataSize=a.dataSize,relocations=a.relocCount,publicCount=a.publicCount,symbols=names,candidateRoots=#roots}
end

-- Decode a GSRenderCameraDesc/HSD_CObj camera exactly far enough for the battle
-- Waza path. Retail cameraPlayOffsetAnime animates the source CObj, reads its
-- eye/interest/FOV each frame, then applies the Waza owner's offset transform.
-- Keep this extractor in source-local coordinates: runtime owns the later
-- owner/arena transform and must never bake one venue's scale into these keys.
local function cameraVecDesc(a,p)
  if not p then return nil end
  local b=a.blob
  local x,y,z=f32(b,p+0x04+1),f32(b,p+0x08+1),f32(b,p+0x0C+1)
  if not (finite(x) and finite(y) and finite(z)) then return nil end
  return {x,y,z}
end
local function cameraAObjEnd(a,aobj)
  if not aobj then return 0 end
  local v=f32(a.blob,aobj+0x04+1)
  return finite(v) and math.max(0,v) or 0
end
local function cameraAObjValues(a,aobj,frame,out,unsupported,ignored,ignoreRoll)
  if not aobj then return end
  local fd=a:ptr(aobj+0x08);local seen=0
  while fd and seen<128 do
    local track,keys=decodeFobj(a,fd)
    local value=fobjValue(keys,frame)
    if track==9 and ignoreRoll then
      -- _cameraOffsetAnimeUpdate intentionally discards the embedded camera's
      -- authored up/roll and replaces it with {0,1,0} before applying the Waza
      -- offset rotation. That makes channel 9 source-irrelevant specifically for
      -- the retail Waza offset-camera path, not a missing CBE approximation.
      if ignored then ignored[9]=true end
    elseif value~=nil and finite(value) then out[track]=value end
    if track~=1 and track~=2 and track~=3 and track~=5 and track~=6 and track~=7
        and track~=10 and track~=11 and track~=12 and not (track==9 and ignoreRoll) then
      unsupported[track]=true
    end
    fd=a:ptr(fd);seen=seen+1
  end
end
local function cameraWObjAObj(a,anim)
  return anim and a:ptr(anim) or nil
end
-- GC6E01 HSD_WObj track 4 is not another scalar position component. Retail
-- WObjUpdateFunc clamps it to [0,1], feeds it to splArcLengthPoint() on the
-- path JObj stored in AObjDesc.obj_id, and HSD_WObjGetPosition later transforms
-- that spline-local point through the path JObj matrix. Keep this decoder close
-- to the recovered HSD_Spline implementation instead of approximating a path
-- with ordinary XYZ lerps.
local function cameraSpline(a,aobj)
  if not aobj then return nil,"WObj path AObj missing" end
  local joint=a:ptr(aobj+0x0C)
  if not joint then return nil,"WObj path AObj obj_id is not a relocated HSD_Joint" end
  local flags=u32(a.blob,joint+0x04+1) or 0
  if not hasFlag(flags,0x4000) then return nil,"WObj path obj_id is not JOBJ_SPLINE" end
  -- HSD_JObjSetupMatrix has additional runtime-only branches for quaternion and
  -- user-defined matrices. We do not infer them from the ordinary Euler SRT.
  if hasFlag(flags,0x20000) then return nil,"WObj path JObj quaternion transform unsupported" end
  if hasFlag(flags,0x800000) then return nil,"WObj path JObj user matrix unsupported" end
  local sp=a:ptr(joint+0x10)
  if not sp then return nil,"WObj path HSD_Spline missing" end
  local typ=a.blob:byte(sp+1);local num=s16(a.blob,sp+0x02+1)
  local tension=f32(a.blob,sp+0x04+1);local cvp=a:ptr(sp+0x08)
  local total=f32(a.blob,sp+0x0C+1);local lenp=a:ptr(sp+0x10);local polyp=a:ptr(sp+0x14)
  if typ==nil or typ<0 or typ>3 or not num or num<2 or num>2048
      or not finite(tension) or not cvp or not finite(total) or total<0 or not lenp then
    return nil,"WObj HSD_Spline descriptor invalid"
  end
  local cvCount=typ==0 and num or (typ==1 and ((num-1)*3+1) or (num+2))
  local cv={}
  for i=0,cvCount-1 do
    local p=cvp+i*12;local x,y,z=f32(a.blob,p+1),f32(a.blob,p+5),f32(a.blob,p+9)
    if not (finite(x) and finite(y) and finite(z)) then return nil,"WObj HSD_Spline control vector invalid" end
    cv[i+1]={x,y,z}
  end
  local seg={}
  for i=0,num-1 do local v=f32(a.blob,lenp+i*4+1);if not finite(v) then return nil,"WObj HSD_Spline segment length invalid" end;seg[i+1]=v end
  if abs(seg[1] or 0)>1e-4 or abs((seg[#seg] or 0)-1)>1e-3 then return nil,"WObj HSD_Spline segment lengths are not normalised" end
  local poly={}
  if typ~=0 then
    if not polyp then return nil,"WObj curved HSD_Spline arc polynomial missing" end
    for i=0,num-2 do
      local c={};for j=0,4 do local v=f32(a.blob,polyp+(i*5+j)*4+1);if not finite(v) then return nil,"WObj HSD_Spline arc polynomial invalid" end;c[j+1]=v end
      poly[i+1]=c
    end
  end
  local rx,ry,rz=f32(a.blob,joint+0x14+1),f32(a.blob,joint+0x18+1),f32(a.blob,joint+0x1C+1)
  local sx,sy,sz=f32(a.blob,joint+0x20+1),f32(a.blob,joint+0x24+1),f32(a.blob,joint+0x28+1)
  local tx,ty,tz=f32(a.blob,joint+0x2C+1),f32(a.blob,joint+0x30+1),f32(a.blob,joint+0x34+1)
  if not (finite(rx) and finite(ry) and finite(rz) and finite(sx) and finite(sy) and finite(sz)
      and finite(tx) and finite(ty) and finite(tz)) then return nil,"WObj path JObj transform invalid" end
  return {type=typ,numcv=num,tension=tension,cv=cv,totalLength=total,segLength=seg,segPoly=poly,
    matrix=localM(rx,ry,rz,sx,sy,sz,tx,ty,tz)}
end
local function splinePolynomial(c,t)
  local t2=t*t;local t3=t2*t;local t4=t3*t
  local q=c[1]*t4+c[2]*t3+c[3]*t2+c[4]*t+c[5]
  -- splArcLengthPolynomial snaps tiny negative roundoff to zero. A materially
  -- negative derivative norm is malformed source, not something to hide.
  if q<0 and q>-0.0010000000474974513 then q=0 end
  if q<0 then return nil end
  return sqrt(q)
end
local function splineArcLength(c,start,finish)
  local dx=(finish-start)*0.125
  local t=start+dx;local middle=0
  for i=2,8 do
    local q=splinePolynomial(c,t);if q==nil then return nil end
    middle=middle+(i%2==0 and 4 or 2)*q;t=t+dx
  end
  local a=splinePolynomial(c,start);local b=splinePolynomial(c,finish)
  if a==nil or b==nil then return nil end
  return dx*(middle+a+b)/3
end
local function splineParameter(s,distance)
  if distance<=0 then return 0 end;if distance>=1 then return 1 end
  local idx=1
  while idx<s.numcv-1 and s.segLength[idx+1]<distance do idx=idx+1 end
  local localT
  if s.type==0 then
    local span=s.segLength[idx+1]-s.segLength[idx]
    if abs(span)<1e-12 then return nil end
    localT=(distance-s.segLength[idx])/span
  else
    local remaining=s.totalLength*(distance-s.segLength[idx]);local lo,hi=0,1;local result=.5
    while abs(hi-lo)>=0.00001 do
      result=(lo+hi)/2
      local length=splineArcLength(s.segPoly[idx],lo,result);if length==nil then return nil end
      if remaining<0.00001+length then hi=result else lo=result;remaining=remaining-length end
    end
    localT=result
  end
  return ((idx-1)+localT)/(s.numcv-1)
end
local function splinePointAtParameter(s,u)
  if u<0 or u>1 then return nil end
  local function mix4(cp,b0,b1,b2,b3)
    return {cp[1][1]*b0+cp[2][1]*b1+cp[3][1]*b2+cp[4][1]*b3,
      cp[1][2]*b0+cp[2][2]*b1+cp[3][2]*b2+cp[4][2]*b3,
      cp[1][3]*b0+cp[2][3]*b1+cp[3][3]*b2+cp[4][3]*b3}
  end
  if u>=1 then
    if s.type==0 then local p=s.cv[s.numcv];return {p[1],p[2],p[3]} end
    if s.type==1 then local p=s.cv[(s.numcv-1)*3+1];return {p[1],p[2],p[3]} end
    if s.type==2 then
      local base=s.numcv-1;local cp={s.cv[base],s.cv[base+1],s.cv[base+2],s.cv[base+3]}
      return mix4(cp,0,1/6,4/6,1/6) -- B-spline at t=1 for cp[-1..+2]
    end
    local p=s.cv[s.numcv+1];return {p[1],p[2],p[3]}
  end
  local q=u*(s.numcv-1);local idx=floor(q);local t=q-idx
  if s.type==0 then
    local a,b=s.cv[idx+1],s.cv[idx+2]
    return {a[1]+t*(b[1]-a[1]),a[2]+t*(b[2]-a[2]),a[3]+t*(b[3]-a[3])}
  elseif s.type==1 then
    local base=idx*3+1;local cp={s.cv[base],s.cv[base+1],s.cv[base+2],s.cv[base+3]};local v=1-t
    return mix4(cp,v*v*v,3*t*v*v,3*t*t*v,t*t*t)
  elseif s.type==2 then
    local base=idx+1;local cp={s.cv[base],s.cv[base+1],s.cv[base+2],s.cv[base+3]}
    local t2=t*t;local t3=t2*t;local v=1-t
    return mix4(cp,v*v*v/6,(4+3*t3-6*t2)/6,(3*(-t3+t2+t)+1)/6,t3/6)
  end
  local base=idx+1;local cp={s.cv[base],s.cv[base+1],s.cv[base+2],s.cv[base+3]};local t2=t*t;local t3=t2*t;local k=s.tension
  return mix4(cp,k*(-t3+2*t2-t),(2-k)*t3+(k-3)*t2+1,(k-2)*t3+(3-2*k)*t2+k*t,k*(t3-t2))
end
local function splineArcPoint(s,distance)
  local u=splineParameter(s,math.max(0,math.min(1,distance)))
  return u and splinePointAtParameter(s,u) or nil
end
local function cameraWObjSample(a,base,aobj,frame,unsupported)
  local pos={base[1],base[2],base[3]};if not aobj then return pos end
  local fd=a:ptr(aobj+0x08);local seen=0;local path,pathWhy;local usePath=false
  local function resolvePath()
    if not usePath then return true end
    if not path then path,pathWhy=cameraSpline(a,aobj) end
    if not path then unsupported[4]=true;return false end
    local x,y,z=point(path.matrix,pos[1],pos[2],pos[3]);pos={x,y,z};usePath=false;return true
  end
  while fd and seen<128 do
    local track,keys=decodeFobj(a,fd);local value=fobjValue(keys,frame)
    if value~=nil and finite(value) then
      if track==4 then
        if not path then path,pathWhy=cameraSpline(a,aobj) end
        local p=path and splineArcPoint(path,math.max(0,math.min(1,value))) or nil
        if not p then unsupported[4]=true else pos=p;usePath=true end
      elseif track>=5 and track<=7 then
        if resolvePath() then pos[track-4]=value end
      end
    end
    fd=a:ptr(fd);seen=seen+1
  end
  resolvePath()
  return pos,pathWhy
end
local function cameraSample(a,static,mainAObj,eyeAObj,interestAObj,frame,unsupported,ignored,ignoreRoll)
  local values={};cameraAObjValues(a,mainAObj,frame,values,unsupported,ignored,ignoreRoll)
  local eye={static.eye[1],static.eye[2],static.eye[3]}
  local focus={static.focus[1],static.focus[2],static.focus[3]}
  -- CObj channels can carry eye/interest directly, although retail camera
  -- resources normally put those vectors in their WObj tracks.
  if values[1]~=nil then eye[1]=values[1] end;if values[2]~=nil then eye[2]=values[2] end;if values[3]~=nil then eye[3]=values[3] end
  if values[5]~=nil then focus[1]=values[5] end;if values[6]~=nil then focus[2]=values[6] end;if values[7]~=nil then focus[3]=values[7] end
  local fov=values[10] or static.fov
  local near=values[11] or static.near
  local far=values[12] or static.far
  -- HSD_CObjAnim evaluates the CObj AObj first and then the two WObjs. Preserve
  -- that order so WObj translation channels win exactly as they do in retail.
  eye=cameraWObjSample(a,eye,eyeAObj,frame,unsupported)
  focus=cameraWObjSample(a,focus,interestAObj,frame,unsupported)
  return {eye=eye,focus=focus,fov=fov,near=near,far=far}
end

function H.extractCameraAnimation(blob,opts)
  opts=opts or {}
  if type(blob)~="string" then return nil,"HSD camera source is not bytes" end
  local a=H.findArchive(blob)
  if not a then return nil,"HSD camera archive not found" end
  local scene=a:publicSymbol("scene_data")
  if not scene then return nil,"HSD camera scene_data missing" end
  -- scene_data's second pointer is GSRenderCameraDesc. This is the same pointer
  -- retail fn_801012E8 passes to fn_800D27FC for an embedded Waza resource.
  local renderDesc=a:ptr(scene+0x04)
  if not renderDesc then return nil,"HSD camera render descriptor missing" end
  local cobj=a:ptr(renderDesc+0x00)
  if not cobj then return nil,"HSD CObj descriptor missing" end
  local projection=u16(a.blob,cobj+0x06+1)
  if projection~=1 then return nil,"unsupported embedded HSD camera projection "..tostring(projection) end
  local eyeDesc=a:ptr(cobj+0x18);local interestDesc=a:ptr(cobj+0x1C)
  local eye=cameraVecDesc(a,eyeDesc);local focus=cameraVecDesc(a,interestDesc)
  if not eye or not focus then return nil,"HSD camera eye/interest descriptors invalid" end
  local fov=f32(a.blob,cobj+0x30+1);local aspect=f32(a.blob,cobj+0x34+1)
  local near=f32(a.blob,cobj+0x28+1);local far=f32(a.blob,cobj+0x2C+1)
  if not (finite(fov) and fov>0 and fov<180 and finite(aspect) and aspect>0
      and finite(near) and near>0 and finite(far) and far>near) then
    return nil,"HSD camera perspective descriptor invalid"
  end
  local mainAObj,eyeAObj,interestAObj
  local animations=a:ptr(renderDesc+0x04)
  local cameraAnim=animations and a:ptr(animations) or nil
  if cameraAnim then
    mainAObj=a:ptr(cameraAnim+0x00)
    local eyeAnim=a:ptr(cameraAnim+0x04);local interestAnim=a:ptr(cameraAnim+0x08)
    eyeAObj=cameraWObjAObj(a,eyeAnim);interestAObj=cameraWObjAObj(a,interestAnim)
  end
  local endFrame=math.max(cameraAObjEnd(a,mainAObj),cameraAObjEnd(a,eyeAObj),cameraAObjEnd(a,interestAObj))
  if endFrame>3600 then return nil,"HSD camera animation exceeds safety frame limit" end
  -- Retail CObjLoad stores either an explicit up vector (flags bit 0) or roll.
  -- Arena.lua currently constructs its view with fixed world-up, so only the
  -- identity orientation is executable without lying about source fidelity.
  -- Preserve the exact descriptor state for diagnostics/future bridging and
  -- fail closed on a non-default orientation.
  local cflags=u16(a.blob,cobj+0x04+1) or 0
  local staticRoll=f32(a.blob,cobj+0x20+1) or 0
  local explicitUp=hasFlag(cflags,1)
  local up=nil
  if explicitUp then
    local upPtr=a:ptr(cobj+0x24)
    if upPtr then
      local ux,uy,uz=f32(a.blob,upPtr+1),f32(a.blob,upPtr+5),f32(a.blob,upPtr+9)
      if not (finite(ux) and finite(uy) and finite(uz)) then return nil,"HSD camera explicit up vector invalid" end
      up={ux,uy,uz}
    else up={0,1,0} end -- CObjLoad's source default lbl_8036C6D4.
  end
  -- cameraPlayOffsetAnime owns more than Waza cameras.  The shared battle-floor
  -- camera (resource 0x007B1800) is driven through the same offset-camera update
  -- path, which reads the authored CObj look-at and then deliberately overwrites
  -- its up vector with world-up before applying offset rotation.  Keep the old
  -- Waza option as a compatibility alias, but expose the actual generic runtime
  -- policy so CameraProbe can audit floor cameras without falsely rejecting an
  -- authored roll/up channel that retail itself discards on this path.
  local offsetCameraWorldUp=opts.offsetCameraWorldUp==true or opts.wazaOffsetWorldUp==true
  local orientationUnsupported=nil
  if offsetCameraWorldUp then
    -- Retail _cameraOffsetAnimeUpdate does GScameraGetLookAt(animation,...), then
    -- immediately writes up={0,1,0}. Embedded CObj roll/up therefore does not
    -- survive into the battle camera; only offsetRotation transforms world-up.
  elseif explicitUp then
    if math.abs(up[1])>1e-6 or math.abs(up[2]-1)>1e-6 or math.abs(up[3])>1e-6 then
      orientationUnsupported="explicit-up-vector"
    end
  elseif not finite(staticRoll) then
    return nil,"HSD camera roll invalid"
  elseif math.abs(staticRoll)>1e-6 then
    orientationUnsupported="roll"
  end
  local static={eye=eye,focus=focus,fov=fov,near=near,far=far}
  local unsupported={};local ignored={};local samples={};local last=math.max(0,math.ceil(endFrame))
  for frame=0,last do
    local s=cameraSample(a,static,mainAObj,eyeAObj,interestAObj,frame,unsupported,ignored,offsetCameraWorldUp)
    samples[#samples+1]={eye=s.eye,focus=s.focus,fov=s.fov,near=s.near,far=s.far}
  end
  local unknown={};for track in pairs(unsupported) do unknown[#unknown+1]=track end;table.sort(unknown)
  local ignoredTracks={};for track in pairs(ignored) do ignoredTracks[#ignoredTracks+1]=track end;table.sort(ignoredTracks)
  -- Track 4 is source-decoded through HSD_WObj's obj_id path JObj and exact
  -- HSD_Spline arc-length semantics above. Never advertise an embedded curve
  -- as executable when a genuinely unsupported channel/transform appears;
  -- WazaHandlers will retain its safe fallback instead.
  local complete=#unknown==0 and orientationUnsupported==nil
  return {revision=H.cameraRevision,source="GC6E01 HSD_CObj frame samples",projection="perspective",aspect=aspect,
    sourceEndFrame=endFrame,frameCount=#samples,sampleStep=1,retailFrameExact=true,
    static={eye=eye,focus=focus,fov=fov,near=near,far=far},samples=samples,
    orientation={flags=cflags,mode=explicitUp and "up" or "roll",roll=staticRoll,up=up},
    orientationPolicy=offsetCameraWorldUp
      and (opts.wazaOffsetWorldUp==true and "retail-waza-world-up-overwrite" or "retail-offset-camera-world-up-overwrite")
      or "hsd-cobj",
    complete=complete,unsupportedTracks=unknown,ignoredTracks=ignoredTracks,unsupportedOrientation=orientationUnsupported}
end
-- Test-only hooks. Nothing in the mod itself reads H._internal; it exists so
-- the matrix algebra behind envelope skinning can be verified directly
-- against known cases instead of only through a full binary archive.
H._internal={mul=mul,ident=ident,localM=localM,point=point,invertAffine=invertAffine,worldScaleTrans=worldScaleTrans,hsdMatrix4x3=hsdMatrix4x3,filterPlaceholderGroups=filterPlaceholderGroups,groupBounds=groupBounds}

function H.describe(blob)
  local d={bytes=type(blob)=="string" and #blob or 0,archives={}}
  if type(blob)~="string" then d.error="not a string";return d end
  local archives=H.findArchives(blob)
  for _,a in ipairs(archives) do d.archives[#d.archives+1]=archiveDiag(a) end
  if #archives==0 then d.error="HSD archive not found" end
  return d
end

-- Arena scenes can contain several HSD_SceneModelSet roots (venue shell,
-- crowd/effects, water). Trainer extraction wants one best actor root, but an
-- arena must combine every semantic model-set root or entire galleries and
-- effect layers disappear. This path intentionally avoids relocation guesses.
local function decodeArchives(blob,opts)
  local session=opts and opts.decodeSession
  if session and session.blob==blob and session.archives then return session.archives end
  local archives=H.findArchives(blob)
  if session then session.blob=blob;session.archives=archives end
  return archives
end

function H.extractSceneModel(blob,opts)
  opts=opts or {}
  if type(blob)~="string" then return nil,"HSD source is not bytes" end
  local archives=decodeArchives(blob,opts);if #archives==0 then return nil,"HSD archive not found" end
  local groups,total={},0
  local min,max={1e30,1e30,1e30},{-1e30,-1e30,-1e30}
  local rootCount,seenRoot=0,{}
  for _,a in ipairs(archives) do
    local roots=semanticModelRoots(a,(tonumber(opts.maxSceneRoots) or 31)+1)
    for _,root in ipairs(roots) do
      if root and not seenRoot[root] then
        seenRoot[root]=true;rootCount=rootCount+1
        if type(opts.progress)=="function" then pcall(opts.progress,rootCount,0) end
        local model,why=extractRoot(a,root,opts)
        -- Empty semantic carriers are valid, but a failed native instance or
        -- exhausted decode budget must not turn a partial venue into a ready
        -- cache just because another modelset happened to contain geometry.
        if not model and opts.nativeSceneInstances and why~="too few renderable vertices" then
          return nil,("scene modelset %d failed: %s"):format(rootCount,tostring(why))
        end
        if model then
          if opts.sourceTextureAnimation==true then
            -- Reuse the texture/TObj objects already decoded for accepted arena
            -- DObjs. A second firstEnabledTexture pass would decompress/decode the
            -- same source atlas again during hard-cache construction.
            local sourceStates={}
            for _,g in ipairs(model.groups or {}) do
              if g.sourceDobj and g.texture and g.sourceTobj then
                sourceStates[g.sourceDobj]={state=g.texture,tobj=g.sourceTobj}
              end
            end
            local texPose,texCount,texWhy=nativeTexturePoseRoot(a,root,0,0,sourceStates)
            for _,g in ipairs(model.groups or {}) do
              if g.texture then
                local state=texPose and texPose.byDobj[g.sourceDobj] or nil
                local tracks=state and state.animation and state.animation.tracks
                if state and type(tracks)=="table" and next(tracks)~=nil and (tonumber(texPose.endFrame) or 0)>0 then
                  local anim=state.animation
                  anim.state="animated";anim.clip=0;anim.endFrame=texPose.endFrame
                  g.sourceTextureAnimation=anim
                elseif texPose or texCount==0 then
                  g.sourceTextureAnimation={revision=1,state="static"}
                else
                  -- Unsupported image/TLUT/projective/unknown source animation
                  -- is deliberately static rather than replaced by guessed UV
                  -- motion. Do not duplicate the diagnostic string into every
                  -- group in a large arena cache; state="blocked" is sufficient
                  -- for the runtime fail-closed contract.
                  g.sourceTextureAnimation={revision=1,state="blocked"}
                end
              end
              g.sourceTobj=nil
            end
          end
          if opts.sourceMaterialAnimation==true then
            local matPose,matCount=nativeArenaMaterialAnimationRoot(a,root,0)
            for _,g in ipairs(model.groups or {}) do
              local state=matPose and matPose.byDobj[g.sourceDobj] or nil
              if state and state.state=="animated" and (tonumber(matPose.endFrame) or 0)>0 then
                state.clip=0;state.endFrame=matPose.endFrame;g.sourceMaterialAnimation=state
              elseif state then
                -- A stream without a usable shared source clock must not become
                -- an invented runtime animation; blocked/static both stay still.
                if state.state=="animated" then state={revision=1,state="blocked"} end
                g.sourceMaterialAnimation=state
              elseif matPose or matCount==0 then
                g.sourceMaterialAnimation={revision=1,state="static"}
              else
                g.sourceMaterialAnimation={revision=1,state="blocked"}
              end
            end
          end
          for _,g in ipairs(model.groups or {}) do groups[#groups+1]=g end
          total=total+(tonumber(model.vertexCount) or 0)
          for k=1,3 do min[k]=math.min(min[k],model.bounds.min[k]);max[k]=math.max(max[k],model.bounds.max[k]) end
        end
      end
    end
  end
  if total<60 then return nil,("no renderable HSD scene modelsets (%d roots)"):format(rootCount) end
  return {groups=groups,vertexCount=total,sceneRoots=rootCount,textureStateVersion=opts.sourceTextureState==true and 1 or nil,
    bounds={min=min,max=max,center={(min[1]+max[1])/2,(min[2]+max[2])/2,(min[3]+max[3])/2}}}
end

-- Return the source HSD animation timing for a model previously decoded by
-- extractModel. Type-2 Waza effect models use this to stay on the retail 60 Hz
-- animation clock instead of guessing a display duration.
function H.nativeAnimationInfo(model,clipIndex)
  if type(model)~="table" or not model.archive or not model.root then return nil,"decoded HSD model required" end
  return nativeClipInfo(model.archive,model.root,clipIndex or 0)
end

-- Sample the source HSD_MatAnimJoint bank that retail GSmodel calls its
-- "texAnim" bank. Returned groups stay aligned with the exact extracted DOBJ /
-- POBJ topology; sourceDobj is extraction-only metadata and is never serialized
-- into the canonical trainer model cache.
function H.nativeMaterialPose(model,clipIndex,frame)
  if type(model)~="table" or not model.archive or not model.root then return nil,"decoded HSD model required" end
  local pose,_,why=nativeMaterialPoseRoot(model.archive,model.root,clipIndex or 0,frame or 0)
  if not pose then return nil,why end
  local groups={}
  for i,g in ipairs(model.groups or {}) do
    local state=pose.byDobj[g.sourceDobj]
    local d=state and state.diffuse or g.diffuse or {1,1,1}
    local pe=state and state.pe or g.pe
    groups[i]={diffuse={d[1] or 1,d[2] or 1,d[3] or 1},
      alpha=(state and state.alpha) or g.alpha or 1,
      ref0=pe and tonumber(pe.ref0) or 0,ref1=pe and tonumber(pe.ref1) or 0}
  end
  return {clip=pose.clip,clipCount=pose.clipCount,animated=pose.animated,groups=groups}
end

-- Sample only the exact affine HSD_TexAnim subset proven by
-- nativeTexturePoseRoot. Groups without an animated enabled TObj remain nil so
-- callers can keep their original source UVs unchanged.
function H.nativeTexturePose(model,clipIndex,frame)
  if type(model)~="table" or not model.archive or not model.root then return nil,"decoded HSD model required" end
  local pose,_,why=nativeTexturePoseRoot(model.archive,model.root,clipIndex or 0,frame or 0)
  if not pose then return nil,why end
  local groups={}
  for i,g in ipairs(model.groups or {}) do
    local state=pose.byDobj[g.sourceDobj]
    groups[i]=state and {affine=state.affine,sourceTextureId=state.sourceTextureId} or false
  end
  return {clip=pose.clip,clipCount=pose.clipCount,animated=pose.animated,groups=groups}
end

-- Re-evaluate one exact source HSD animation frame against the same archive/root
-- selected by extractModel. Keeping root identity fixed guarantees topology is
-- stable enough for Waza GPU morph pages and avoids candidate-root reselection.
function H.extractNativePose(model,clipIndex,frame,opts)
  if type(model)~="table" or not model.archive or not model.root then return nil,"decoded HSD model required" end
  opts=opts or {}
  local o={}
  for k,v in pairs(opts) do o[k]=v end
  o.nativePose={clip=tonumber(clipIndex) or 0,frame=tonumber(frame) or 0}
  return extractRoot(model.archive,model.root,o)
end

-- Enumerate every renderable HSD JOBJ model root in a source blob.
-- Capture extraction uses this because the retail snatch_*.fdat member can
-- contain several HSD roots: the physical ball is not guaranteed to be the
-- largest root and is not guaranteed to live inside a Waza type-2 payload.
function H.extractModels(blob,opts)
  opts=opts or {}
  if type(blob)~="string" then return nil,"HSD source is not bytes" end
  local archives=H.findArchives(blob)
  if #archives==0 and type(H.findArchivesDeep)=="function" then archives=H.findArchivesDeep(blob,#blob) end
  if #archives==0 then return nil,"HSD archive not found" end
  local out={};local rootCount=0;local lastBudget=nil
  for _,a in ipairs(archives) do
    local roots=opts.semanticRootsOnly
      and semanticModelRoots(a,opts.maxRoots or 192)
      or candidateRoots(a,opts.maxRoots or 192)
    for ri,root in ipairs(roots) do
      rootCount=rootCount+1
      if type(opts.progress)=="function" and (ri==1 or ri%8==0) then pcall(opts.progress,ri,#roots) end
      local model,why,stats=extractRoot(a,root,opts)
      if why then lastBudget=why end
      if model then
        model.archive=a;model.root=root;model.stats=stats
        model.semanticRootsOnly=opts.semanticRootsOnly==true
        model.semanticRootCount=#roots
        out[#out+1]=model
      end
    end
  end
  if #out==0 then
    local suffix=lastBudget and ("; last guard="..tostring(lastBudget)) or ""
    return nil,("no renderable HSD JOBJ models found (%d archive%s, %d candidate root%s%s)"):format(
      #archives,#archives==1 and "" or "s",rootCount,rootCount==1 and "" or "s",suffix)
  end
  table.sort(out,function(a,b)return (tonumber(a.vertexCount) or 0)>(tonumber(b.vertexCount) or 0) end)
  return out
end

function H.extractRetailModelBound(blob,opts)
  opts=opts or {}
  if type(blob)~="string" then return nil,"HSD source is not bytes" end
  local animationIndex=tonumber(opts.animationIndex)
  if animationIndex==nil then return nil,"retail-bound exact animation index required" end
  local archives=decodeArchives(blob,opts)
  if #archives==0 then return nil,"HSD archive not found" end
  local candidates={}
  for ai,a in ipairs(archives) do
    local roots=semanticModelRoots(a,opts.maxRoots or 64)
    for ri,root in ipairs(roots) do candidates[#candidates+1]={archive=a,archiveIndex=ai,root=root,rootIndex=ri,rootCount=#roots} end
  end
  if #candidates==0 then return nil,"retail-bound semantic scene model root unavailable" end
  local selected=nil
  if opts.root then
    for _,c in ipairs(candidates) do if c.root==opts.root and (not opts.archive or c.archive==opts.archive) then selected=c;break end end
    if not selected then return nil,"retail-bound requested source root unavailable" end
  elseif opts.rootIndex then
    local wanted=math.max(1,floor(tonumber(opts.rootIndex) or 1))
    selected=candidates[wanted]
    if not selected then return nil,"retail-bound requested semantic root index unavailable" end
  elseif #candidates==1 then selected=candidates[1]
  else
    -- Multiple scene modelsets can legitimately include body/shadow/helper
    -- resources. Retail GSresGetResource owns one exact GSmodel; choosing the
    -- largest or first root here would recreate the heuristic we are removing.
    return nil,("retail-bound source root ambiguous (%d semantic roots)"):format(#candidates)
  end
  local bound,why,budget=extractRetailBoundRoot(selected.archive,selected.root,animationIndex,opts)
  if bound then
    bound.archiveIndex=selected.archiveIndex;bound.semanticRootIndex=selected.rootIndex
    bound.semanticRootCount=selected.rootCount;bound.root=selected.root;bound.archive=selected.archive
  end
  return bound,why,budget
end

-- Exact-root variant for callers that already own the decoded source GSmodel
-- root. It does not re-select by vertex count and is the safe bridge for a
-- Pokemon extraction session once retail resource-root provenance is known.
function H.extractRetailModelBoundFromModel(model,animationIndex,opts)
  if type(model)~="table" or not model.archive or not model.root then return nil,"decoded HSD model required" end
  if model.semanticRootsOnly~=true then return nil,"retail-bound decoded model lacks semantic-root provenance" end
  local semantic=false
  for _,root in ipairs(semanticModelRoots(model.archive,(opts and opts.maxRoots) or 192)) do
    if root==model.root then semantic=true;break end
  end
  if not semantic then return nil,"retail-bound decoded model root is not a semantic scene model root" end
  return extractRetailBoundRoot(model.archive,model.root,animationIndex,opts or {})
end

function H.extractModel(blob,opts)
  opts=opts or {}
  if type(blob)~="string" then return nil,"HSD source is not bytes" end
  local archives=decodeArchives(blob,opts);if #archives==0 then return nil,"HSD archive not found" end
  local best=nil;local rootCount=0;local lastBudget=nil;local maxPartial=0;local shapeSeen=0
  for _,a in ipairs(archives) do
    -- Character PKX files expose authoritative model roots through scene_data.
    -- When semanticRootsOnly is requested (PokemonActors), do NOT let a larger
    -- relocation-derived false root beat the real model merely because garbage
    -- pointers happened to decode into extra triangles.
    local roots=opts.semanticRootsOnly
      and semanticModelRoots(a,opts.maxRoots or 192)
      or candidateRoots(a,opts.maxRoots or 192)
    for ri,root in ipairs(roots) do
      rootCount=rootCount+1
      if type(opts.progress)=="function" and (ri==1 or ri%8==0) then pcall(opts.progress,ri,#roots) end
      local model,why,stats=extractRoot(a,root,opts)
      if why then lastBudget=why end
      if stats then
        if (stats.vertices or 0)>maxPartial then maxPartial=stats.vertices or 0 end
        if (stats.shapePobjs or 0)>shapeSeen then shapeSeen=stats.shapePobjs or 0 end
      end
      if model and (not best or model.vertexCount>best.vertexCount) then
        best=model;best.archive=a;best.root=root;best.stats=stats
        best.semanticRootsOnly=opts.semanticRootsOnly==true
        best.semanticRootCount=#roots
      end
    end
  end
  if not best then
    local suffix=lastBudget and ("; last guard="..tostring(lastBudget)) or ""
    if opts.semanticRootsOnly then suffix=suffix.."; semantic scene-modelset roots only" end
    suffix=suffix..("; max partial=%d; shape POBJs=%d"):format(maxPartial,shapeSeen)
    return nil,("no renderable HSD JOBJ model found (%d archive%s, %d candidate root%s%s)"):format(#archives,#archives==1 and "" or "s",rootCount,rootCount==1 and "" or "s",suffix)
  end
  return best
end
H.reflectionTextureMatrix=reflectionTextureMatrix
H._test={packedVertexColor=packedVertexColor,decodeFobj=decodeFobj,fobjValue=fobjValue,nativeAnimations=nativeAnimations,nativeMaterialAnimations=nativeMaterialAnimations,nativeMaterialPoseRoot=nativeMaterialPoseRoot,nativeTexturePoseRoot=nativeTexturePoseRoot,nativeArenaMaterialAnimationRoot=nativeArenaMaterialAnimationRoot,textureAffine=textureAffine,localMatrix=localM,inheritedScale=inheritedScale,multiply=mul,nativePose=nativePose,textureBaseMatrix=textureBaseMatrix,sourceTextureMatrix=sourceTextureMatrix,reflectionTextureMatrix=reflectionTextureMatrix,applySourceTextureState=applySourceTextureState,decodeTextureObject=decodeTextureObject,extractRoot=extractRoot,cameraSample=cameraSample,
  splinePointAtParameter=splinePointAtParameter,splineArcPoint=splineArcPoint,
  retailDirectWidth=retailDirectWidth,retailDobjPassFlag=retailDobjPassFlag,retailJobjHasPass=retailJobjHasPass,
  retailStrictInverse=retailStrictInverse,retailEnvelopeNodeMatrix=retailEnvelopeNodeMatrix,retailEnvelopePalette=retailEnvelopePalette,
  retailBoundDisplay=retailBoundDisplay,extractRetailBoundRoot=extractRetailBoundRoot,nativeRetailBoundPose=nativeRetailBoundPose}
return H
