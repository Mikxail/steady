cluster = require 'cluster'
stdio   = require './stdio'

class exports.Worker
    constructor: (@workerFunc, @options = {}) ->
        @defaultOut = @options.stdout or process.stdout
        @defaultErr = @options.stderr or process.stderr
        @reopenStdio()

        @isFinishing = false

        @restoreFn = undefined
        @restoreQueue = []

        @servers = []
        @connections = {}

        @listenSignals()
        @listenMessages()

    start: () ->
        # @servers = @options.worker()
        @servers = @workerFunc()
        @waitServers()


    waitServers: () ->
        return @sendReady() if @servers.length is 0
        wait = 0
        done = =>
            if --wait is 0
                @sendReady()

        for server in @servers
            wait++
            if server.on?
                server.on 'listening', () =>
                    done()
            else
                done()


    sendReady: () ->
        process.send {msg: "ready"}


    listenSignals: () ->
        process.on "SIGHUP", -> # Ignore signal.
        process.on "SIGUSR2", -> # Ignore signal
        process.on "SIGTERM", => # soft stop(grab all connections and send to master)
            @onTermSig()
        process.on "SIGPIPE", -> # Ignore signal


    listenMessages: () ->
        process.on "message", (msg, handle) =>
            switch msg.msg
                when "finish" # Master says we should die.
                    @onFinishMsg(msg, handle)

                when "conn" # We are alive and getting open connections from old worker.
                    @onConnMsg(msg, handle)

                when "chstdio"
                    @reopenStdio()

    onFinishMsg: (msg, handle) ->
        return if @isFinishing
        @isFinishing = true

        # Close servers
        for server, idx in @servers
            do (server, idx) ->
                if server.close?
                    console.log "Server #{idx} call close..."
                    server.close ->
                        console.log "Server #{idx} closed."

        # Send all active connections to master.
        for id, {conn, saveFn} of @connections
            connData = saveFn()
            # console.log "Sending conn", connData
            process.send {msg: "conn", connData}, conn, {track: true}
            conn.destroy()


    onConnMsg: (msg, handle) ->
        console.log "Worker conn"
        if @restoreFn?
            @restoreFn(handle, msg.connData)
        else
            @restoreQueue.push {handle, connData: msg.connData}

    onTermSig: () ->
        if @isFinishing
            return process.exit(0)
        # if user do: $pkill -TERM steady
        # we want stop all. Delay for waiting Monitor can send {msg: "finish"}
        setTimeout =>
            return if @isFinishing
            process.send {msg: "quit"}
            # @onFinishMsg()
        , 300


    reopenStdio: (stdout = @defaultOut, stderr = @defaultErr) ->
        stdio.reopen stdout, stderr

    save: (conn, saveFn) ->
        id = Math.random().toString(36)
        @connections[id] = {conn, saveFn}
        conn.on 'close', => delete @connections[id]


    restore: (fn) ->
        @restoreFn = fn
        for {handle, connData} in @restoreQueue
            @restoreFn(handle, connData)
        @restoreQueue = []

