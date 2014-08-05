util        = require 'util'
path        = require 'path'
cluster     = require 'cluster'
daemon      = require 'daemon'
{Monitor}   = require './monitor'
{Worker}    = require './worker'
log         = require './log'
info        = require './info'
control     = require './control'


steady = exports

# Master variables
isStarted = false
# startedScripts = {}
# startedMonitors = []
startedMonitors = {}

# Worker variables
imWorker = undefined
workerServers = []


# steady.run = () ->
#     return if not cluster.isMaster

steady.daemon = () ->
    return if not cluster.isMaster
    daemon
        stdout: process.stdout
        stderr: process.stderr

steady.replaceConsole = () ->
    log
        always: true
        prefix: if cluster.isMaster then "M" else "W"

steady.add = (servers) ->
    return if cluster.isMaster
    if not util.isArray servers
        servers = [servers]
    for s in servers
        if workerServers.indexOf(s) is -1
            workerServers.push s
    workerServers

steady.save = () ->
    return if cluster.isMaster
    imWorker?.save.apply imWorker, arguments

steady.restore = () ->
    return if cluster.isMaster
    imWorker?.restore.apply imWorker, arguments




steady.start = (script, options) ->
    if typeof script isnt "string"
        options = script
        script = options?.script or undefined
    options ?= {}
    options.workersCount ?= 1
    options.script ?= script
    for out in ['stdout', 'stderr']
        if options?[out] and typeof options[out] is "string" and options[out] isnt 'ignore'
            options[out] = path.resolve(options[out])
    sourceRunStr = (options.argv ? []).join(' ')
    if cluster.isMaster
        if not startedMonitors[script]?.length
            options.uuid ?= process.pid
            @_startWorkers(options)
            process.title = "[steady master] #{sourceRunStr}".trim()
        if not isStarted
            @_listenSignals()
            @_listenControl()
            isStarted = true
    else
        workerFunc = () ->
            process.argv = options.argv or []
            requireServers = []
            if script? and script isnt undefined
                requireServers = require "#{script}"
                steady.add requireServers
            workerServers or []
        imWorker = new Worker(workerFunc, options)
        imWorker.start()
        process.title = "[steady ##{process.env.UUID}] #{sourceRunStr}".trim()


steady.startControl = (opts = {}) ->
    return if not cluster.isMaster
    control.start(opts)
    return

steady.stop = (monitors = @_getAllMonitors()) ->
    return if not cluster.isMaster
    for m in monitors
        m.stopWorker()
    return

steady.reload = (monitors = @_getAllMonitors()) ->
    return if not cluster.isMaster
    for m in monitors
        m.reloadWorker()
    return



# steady.info = (monitors = @_getAllMonitors(), callback) ->
#     if not cluster.isMaster
#         return @_selfInfo callback
#     ret = []
#     wait = 0
#     done = () ->
#         if --wait is 0
#             callback null, ret
#     for m in monitors then do (m) ->
#         info.info m.worker.process, (err, data) ->
#             o = {}
#             o[m.process.pid] = data
#             ret.push o

# steady._selfInfo = (callback) ->
#     return callback new Erorr "Can be called only from worker" if cluster.isMaster
#     info.info process, (err, data) ->
#         o = {}
#         o[process.pid] = data
#         callback null, o


steady.fork = (options = {}) ->
    return if not cluster.isMaster
    monitor = new Monitor(options)
    script = options.script
    startedMonitors[script] ?= []
    startedMonitors[script].push {monitor, options}

    monitor.on "exit", =>
        @_onMonitorExit script, monitor

    monitor.on "message", (msg, handle) =>
        switch msg.msg
            when "conn"
                @_onMonitorConnMsg(script, msg, handle)

    return monitor



steady._startWorkers = (options = {}) ->
    return if not cluster.isMaster
    for [1..options.workersCount]
        @fork(options)

steady._listenSignals = () ->
    return if not cluster.isMaster
    process.on "SIGPIPE", =>
        @startControl {exitOnDisconnect: true}
        # for script, monitors of startedMonitors
        #     @fork(monitors[0].options)
    return

steady._listenControl = () ->
    control.on "cmd-logs", (sock) =>
        monitors = steady._getAllMonitors()
        stdout = if typeof monitors[0].options.stdout is "string" then monitors[0].options.stdout else null
        stderr = if typeof monitors[0].options.stderr is "string" then monitors[0].options.stderr else null
        ret = JSON.stringify({stdout, stderr})
        sock.write "#{ret}\n"
        sock.destroy()

    control.on "cmd-spawn", (sock) =>
        for script, monitors of startedMonitors
            @fork(monitors[0].options)
            sock.write "Spawned '#{script}'\n"
        sock.destroy()

# steady._listenMessages = () ->
#     return if not cluster.isMaster


steady._onMonitorConnMsg = (script, msg, handle) ->
    return if not cluster.isMaster
    monitors = startedMonitors[script]
    return if not monitors?.length
    monitors = monitors.filter (m) -> not m.monitor.worker.suicide
    randMonitor = monitors[Math.floor(Math.random()*monitors.length)].monitor
    randMonitor.emit "conn", msg, handle
    randMonitor

steady._onMonitorExit = (script, monitor) ->
    return if not cluster.isMaster
    for m, idx in (startedMonitors[script] ? [])
        if m.monitor is monitor
            startedMonitors[script]?.splice idx, 1
            break
    if startedMonitors[script]?.length is 0
        delete startedMonitors[script]

steady._getAllMonitors = () ->
    ret = []
    for script, monitors of startedMonitors
        for m in monitors
            ret.push m.monitor
    ret
