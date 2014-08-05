# usage = require 'usage'

info = exports

info.mem = (p, cb) ->
    console.log "-----call info.mem"
    cb null, p.memoryUsage()

# info.cpu = (p, cb) ->
#     usage.lookup p.pid, cb

# info.info = (p, cb) ->
#     @cpu p, (err, cpuInfo) =>
#         return cb err if err?
#         @mem p, (err, memInfo) ->
#             return cb err if err?
#             cb null, {mem: memInfo, cpu: cpuInfo}

info.info = (p, cb) ->
    console.log "-----call info"
    @mem p, cb