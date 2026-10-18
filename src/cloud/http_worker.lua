local job,channel=...
package.path=job.packagePath or package.path
require('love.system');require('love.filesystem');require('love.data');require('love.timer')
local ok,status,body=pcall(function()
 return require('src.cloud.Http').request(job.method,job.url,job.opts)
end)
if not ok then status,body=nil,'Cloud network request failed: '..tostring(status) end
channel:push({status=status,body=body})
