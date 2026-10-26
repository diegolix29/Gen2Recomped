-- Compare render inputs without formatting a new string every frame. Tokens
-- change only against the last committed (actually rendered) snapshot.
local M={}
function M.new()
 local current,published={},{}
 local n,previousN,publishedN,version=0,0,0,0
 local changed=false
 local s={}
 function s.begin() previousN=n;n=0;changed=false end
 function s.put(value)
  n=n+1;current[n]=value
  if published[n]~=value then changed=true end
 end
 function s.token()
  for i=n+1,previousN do current[i]=nil end
  previousN=n
  return (changed or n~=publishedN) and version+1 or version
 end
 function s.commit()
  version=s.token()
  for i=1,n do published[i]=current[i] end
  for i=n+1,publishedN do published[i]=nil end
  publishedN=n
 end
 return s
end
return M
