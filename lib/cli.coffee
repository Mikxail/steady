path          = require 'path'
{Cmd}         = require './cmd'
steady        = require './steady'
child_process = require 'child_process'
net           = require 'net'

cli = exports
app = new Cmd

help = """
    Usage: steady [options] [action] SCRIPT|PID [script-options]

    Actions:
        start                   Start SCRIPT as a daemon
        stop <PID>              Stop the daemon SCRIPT
        stopall                 Stop all running pculster scripts
        restart <PID>           Restart the daemon SCRIPT
        restartall              Restart all running pculster scripts
        list                    List all runing pculster scripts
        worker <PID>            Add more workers to exist master process
        remworker <PID>         Remove workers from exist master process
        logs <PID>              Exec "tail" command for LOGFILE or ERRFILE(if LOGFILE doen't exist)

    Options:
        -d, --daemon            Start as daemon
        -r                      Replace console
        -m MAX, --max           Only run the specified script MAX times
        -l LOGFILE, --logFile   Logs stdout and stderr from child script to LOGFILE
        -o OUTFILE, --outFile   Logs stdout from child script to OUTFILE
        -e ERRFILE, --errFile   Logs stderr from child script to ERRFILE
        -s, --silent            Silent mode
        -u MSEC, --minUptime    Minimum uptime (millis) for a script to not be considered "spinning"
        -k MSEC, --maxDelay     Maximum delay (millis) before force kill old worker
        -t MSEC, --maxWait      Maximum wait starting worker
        -w COUNT, --workers     Number of workers
"""
        # -a, --append            Append logs
        # -f, --fifo              Stream logs to stdout


actions = [
    'start'
    'stop'
    'stopall'
    'restart'
    'restartall'
    'list'
]

argvOptions =
    'daemon':    {alias: 'd', boolean: true, default: false}        # ok
    'max':       {alias: 'm', default: 5}                           # ok
    'minUptime': {alias: 'u', default: 20000}                       # ok
    'maxDelay':  {alias: 'k', default: 5000}                        # ok
    'maxWait':   {alias: 't', default: 5000}                        # ok
    'logFile':   {alias: 'l'}                                       # ok
    'outFile':   {alias: 'o'}                                       # ok
    'errFile':   {alias: 'e'}                                       # ok
    'silent':    {alias: 's', boolean: true, default: false}        # ok
    # 'append':    {alias: 'a', boolean: true, default: true}
    # 'fifo':      {alias: 'f', boolean: true, default: false}
    'workers':   {alias: 'w', default: 1}                           # ok
    'replaceConsole': {alias: 'r', boolean: true, default: false}   # ok


app.opts argvOptions

app.help help


getMasters = (callback) ->
    child = child_process.exec 'ps ax | grep "[s]teady master" | awk \'{print $1}\'', (err, stdout, stderr) ->
        pids = (stdout+"").split(/\r?\n/).filter(Boolean)
        callback null, pids

getWorkersByMaster = (pid, callback) ->
    child = child_process.exec 'ps ax | grep "[s]teady #'+pid+'" | awk \'{print $1}\'', (err, stdout, stderr) ->
        pids = (stdout+"").split(/\r?\n/).filter(Boolean)
        callback null, pids


sendSignal = (pid, sig, callback) ->
    child = child_process.exec "kill -#{sig} #{pid}", (err, stdout, stderr) ->
        callback err, stdout

sendCommand = (pid, command, callback) ->
    sendSignal pid, "PIPE", ->
        setTimeout ->
            socket = net.connect "/tmp/steadycontrol.#{pid}.sock"

            socket.on "connect", ->
                socket.write "#{command}\n"
            socket.on "error", (err) ->
                callback err
            datas = ""
            socket.on "data", (chunk) ->
                datas += chunk
            socket.on "close", ->
                callback null, datas
        , 50

restartByPid = (pid, callback) ->
    getMasters (err, pids) ->
        return callback err if err?
        if pids.indexOf(pid) is -1
            return callback "Can't fount steady process with pid '#{pid}'"

        sendSignal pid, "HUP", (err) ->
            callback err

stopByPid = (pid, callback) ->
    getMasters (err, pids) ->
        return callback err if err?
        if pids.indexOf(pid) is -1
            return callback "Can't fount steady process with pid '#{pid}'"

        sendSignal pid, "TERM", (err) ->
            callback err

workerByPid = (pid, callback) ->
    getMasters (err, pids) ->
        return callback err if err?
        if pids.indexOf(pid) is -1
            return callback "Can't fount steady process with pid '#{pid}'"

        sendCommand pid, "spawn", (err) ->
            callback err

remworkersByPid = (pid, count, callback) ->
    getMasters (err, pids) ->
        return callback err if err?
        if pids.indexOf(pid) is -1
            return callback "Can't fount steady process with pid '#{pid}'"

        getWorkersByMaster pid, (err, wpids) ->
            for idx in [0...count]
                wpid = wpids[idx]
                if wpid?
                    sendSignal wpid, "TERM", (err) ->
                        callback err

logsByPid = (pid, opts, callback) ->
    getMasters (err, pids) ->
        return callback err if err?
        # if pids.indexOf(pid) is -1
        #     return callback "Can't fount steady process with pid '#{pid}'"

        sendCommand pid, "logs", (err, data) ->
            return callback err if err?
            try
                data = JSON.parse(data)
            catch e
                callback e
            logFile = data.stderr or data.stdout
            if not logFile?
                return callback new Error "process hasn't logFile"

            command = "tail #{logFile} #{opts.join(' ')}"
            child_process.exec command, (err, stdout, stderr) ->
                callback null, stdout

app.cmd "start (.+)", (options, [file], appendOptions) ->
    sourceFile = path.resolve process.cwd(), file

    if options.replaceConsole is true
        steady.replaceConsole()

    if options.daemon is true
        steady.daemon()

    opts =
        argv: [path.basename(process.argv[1])].concat(file, (appendOptions or []))

        # sourceFile: options.sourceFile
        # sourceDir: options.sourceDir
        # sourceRunStr: options.sourceRunStr

        maxRestartAttempts: options.max
        workersCount: options.workers
        minWorkTime: options.minUptime
        maxDestroyDelay: options.maxDelay
        maxStartWait: options.maxWait

        stdout: options.outFile or options.logFile or process.stdout
        stderr: options.errFile or options.logFile or process.stderr

    if  options.silent is true
        opts.stdout = 'ignore'
        opts.stderr = 'ignore'

    if options.daemon is true
        if opts.stdout is process.stdout
            opts.stdout = 'ignore'
        if opts.stderr is process.stderr
            opts.stderr = 'ignore'

    steady.start sourceFile, opts


app.cmd "worker (.+)", (options, [pid]) ->
    for [1..options.workers]
        workerByPid pid, (err) ->
            return console.error err if err?
            console.log "Process '#{pid}' create new workers"

app.cmd "remworker (.+)", (options, [pid]) ->
    remworkersByPid pid, options.workers, (err) ->
        return console.error err if err?
        console.log "Process '#{pid}' remove workers"


app.cmd "list", ->
    child = child_process.exec 'ps ax | grep "[s]teady master"', (err, stdout, stderr) ->
        console.log stdout

app.cmd "restart (.+)", (options, [pid]) ->
    restartByPid pid, (err) ->
        return console.error err if err?
        console.log "Process '#{pid}' restarted"

app.cmd "stop (.+)", (options, [pid])->
    stopByPid pid, (err) ->
        return console.error err if err?
        console.log "Process '#{pid}' stopped"

app.cmd "restartall", ->
    getMasters (err, pids) ->
        return console.error err if err?
        for pid in pids then do (pid) ->
            restartByPid pid, (err) ->
                return console.error err if err?
                console.log "Process '#{pid}' restarted"

app.cmd "stopall", ->
    getMasters (err, pids) ->
        return console.error err if err?
        for pid in pids then do (pid) ->
            stopByPid pid, (err) ->
                return console.error err if err?
                console.log "Process '#{pid}' stopped"

app.cmd "logs (.+)", (options, [pid], appendOptions)->
    logsByPid pid, appendOptions, (err, data) ->
        return console.error err if err?
        console.log data

cli.run = ->
    app.start()


