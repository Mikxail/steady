{EventEmitter}  = require 'events'
cluster         = require 'cluster'
stdio           = require './stdio'

class exports.Monitor extends EventEmitter
    constructor: (@options = {}) ->
        @defaultOut = @options.stdout or process.stdout
        @defaultErr = @options.stderr or process.stderr

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
        @reopenStdio()

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
        console.error Date(), "Stop oldWorker"
        w.suicide = true
        if w.state not in ['online', 'listening']
            console.error Date(), "oldWorker has state '#{w.state}'. Destroy it."
            w.destroy()
            return
        w.send {msg: "finish"}
        timeout = setTimeout ->
            console.error Date(), "Destroying worker."
            if not w.kill? # node 0.8
                w.process?.kill? 'SIGKILL'
            else # node v 0.10
                w.destroy? 'SIGKILL'
        , @maxDestroyDelay
        w.on 'exit', =>
            console.error Date(), "oldWorker exit"
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
        console.error Date(), "Ready msg"
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
                console.error Date(), "max restartAttempts: '#{@restartAttempts}' of '#{maxRestartAttempts}'. do exit"
                process.exit() # Worker cannot start after several attempts. Master dies.
        else
            restartAttempts = 0

        console.error Date(), "Worker crashed. Restarting..."
        setTimeout =>
            @startNewWorker()
        , restartAttempts*restartAttempts * 100

    onStartTimeout: ->
        console.error Date(), "Worker can't starting. Destroying worker."
        @worker.destroy()
        return if not @oldWorker?
        @worker = @oldWorker