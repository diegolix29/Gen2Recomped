-- Shared by manual imports, Android inbox picks and batch scans, including
-- their worker-thread paths. A DS header alone never authorizes extraction.
local V={}
V.SIZES={}
for _,mib in ipairs({1,2,4,8,16,32,128,256}) do V.SIZES[mib*1048576]=true end
local identities=require('src.import.NdsTrimIdentity')
local function dsIdentity(bytes)
  if type(bytes)~='string' or #bytes<0x200 then return nil end
  local code=bytes:sub(13,16)
  for version,rec in pairs(identities.games) do
    if rec.code==code and 131072*2^bytes:byte(21)==rec.capacity then return rec,version end
  end
end
-- This is a cheap read/hash prefilter, not acceptance. Files shorter than
-- the known content extent must not be treated as merely trimmed padding.
function V.isCandidate(size,header)
  if V.SIZES[size] then return true end
  local rec=dsIdentity(header)
  return rec~=nil and size>=rec.contentSize and size<rec.capacity
end
function V.sha1(bytes)
  local digest=love.data.hash('sha1',bytes)
  if type(digest)=='userdata' then digest=digest:getString() end
  return love.data.encode('string','hex',digest)
end
function V.identify(bytes,hash)
  assert(type(bytes)=='string','ROM bytes required')
  hash=hash or V.sha1
  local GV=require('src.core.GameVersion')
  local sourceHash=hash(bytes)
  local result={hash=sourceHash,sourceHash=sourceHash,size=#bytes,version=GV.forSha1(sourceHash)}
  if result.version then return result end
  local rec,version=dsIdentity(bytes)
  if not rec or #bytes<rec.contentSize or #bytes>=rec.capacity then return result end
  -- Match the registry too: an identity cannot enable a removed revision.
  if GV.forSha1(rec.sha1)~=version then return result end
  if bytes:find('[^\255]',rec.contentSize+1) then return result end
  for i,expected in ipairs(rec.chunks) do
    local start=(i-1)*identities.chunkSize+1
    local finish=math.min(i*identities.chunkSize,rec.contentSize)
    if hash(bytes:sub(start,finish))~=expected then return result end
  end
  -- All missing bytes are proven to have been FF in the verified full dump.
  -- Keep the actual file hash for diagnostics, use the canonical identity
  -- for the existing manifests/cache markers. The source file is untouched.
  result.hash=rec.sha1;result.version=version;result.trimmed=true
  return result
end
return V
