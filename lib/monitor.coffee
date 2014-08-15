{EventEmitter}  = require 'events'
cluster         = require 'cluster'
stdio           = require './stdio'

class exports.Monitor extends EventEmitter
    constructor: (@options = {}) ->
        @defaultOut = @options.stdout or process.stdout
        @defaultErr = @options.stderr or process.stderr
        @reopenStdio()

        @restartAttempts = 0
        @maxRestartAttempts = options.maxRestartAttempts or 5
        @minWorkTime = options.minWorkTime or 20000
        @maxDestroyDelay = options.maxDestroyDelay or 5000
        @maxStartWait = options.maxStartWait or 5000

        @worker = undefined
        @oldWorker = undefined
        @startTimeout = undefined

        @listenSignals()

        @startNewWorker()

    startNewWorker: () ->
        @forkTime = Date.now()

        @oldWorker = @worker
        @worker = cluster.fork({UUID: @options.uuid})

        @listenMessages()
        @startTimeout = setTimeout (=> @onStartTimeout()), @maxStartWait

    reloadWorker: () ->
        @startNewWorker()

    stopWorker: (w = @worker) ->
        return if not w?
        console.log "Stop oldWorker"
        w.suicide = true
        if not w.state in ['online', 'listening']
            console.log "oldWorker has state '#{w.state}'. Destroy it."
            w.destroy()
            return
        w.send {msg: "finish"}
        timeout = setTimeout (-> console.log "Destroying worker."; w.destroy()), @maxDestroyDelay
        w.on 'exit', =>
            console.log "oldWorker exit"
            @worker = undefined
            clearTimeout(timeout)
            @emit "exit"
        w.disconnect()

    listenSignals: () ->
        process.on "SIGHUP", => # Reload worker
            @startNewWorker()

        process.on "SIGTERM", => # Stop worker (soft stop)
            @stopWorker @worker

        process.on "SIGUSR2", => # Reopen logs
            @reopenStdio()
            @reopenWorkerStdio()

    reopenStdio: (stdout = @defaultOut, stderr = @defaultErr) ->
        stdio.reopen stdout, stderr

    reopenWorkerStdio: () ->
        @worker.send {msg: "chstdio"}

    listenMessages: ->
        @worker.on "message", (msg, handle) =>
            switch msg.msg
                when "conn"
                    @onConnMsg(msg, handle)
                when "ready"
                    @onReadyMsg(msg)
                when "quit"
                    @onQuitMsg(msg)

        @on "conn", (msg, handle) =>
            switch msg.msg
                when "conn"
                    @onConnMsg(msg, handle)

        @worker.on "exit", @onExit.bind(@, @worker)
        #@worker.on "online", -> console.log "Worker online"
        #@worker.on "exit", (code, signal) -> console.log "Worker exited #{code}, #{signal}"
        #@worker.on "listening", (address)-> console.log "Worker listening", address.port


    onReadyMsg: () ->
        console.log "Ready msg"
        clearTimeout @startTimeout if @startTimeout?
        return unless @oldWorker
        @stopWorker(@oldWorker)
        @oldWorker = undefined


    onConnMsg: (msg, handle) ->
        if @worker? and not @worker.suicide
            # send connections to worker
            @worker.send msg, handle
        else
            # throw new Error()
            # send connections to steady
            @emit "message", msg, handle

    onQuitMsg: (msg) ->
        @stopWorker()
        # @worker.suicide = true

    onExit: (w) ->
        return if w.suicide # Clean exit.

        workTime = Date.now() - @forkTime
        if workTime < @minWorkTime
            if ++@restartAttempts >= @maxRestartAttempts
                process.exit() # Worker cannot start after several attempts. Master dies.
        else
            restartAttempts = 0

        console.log "Worker crashed. Restarting..."
        setTimeout =>
            @startNewWorker()
        , restartAttempts*restartAttempts * 100

    onStartTimeout: ->
        console.log "Worker can't starting. Destroying worker."
        @worker.destroy()
        return if not @oldWorker?
        @worker = @oldWorker