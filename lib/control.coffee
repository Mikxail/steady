path            = require 'path'
net             = require 'net'
{Socket}        = net.Socket
{EventEmitter}  = require 'events'

class Sock extends EventEmitter
    constructor: (@_socket) ->
        @chunks = ""

        @_socket.on "data", (chunk)=>
            @chunks += chunk
            @_checkChunks()

    _checkChunks: ->
        chunksArr = @chunks.split(/\r?\n/)
        commands = chunksArr.splice(0, chunksArr.length-1)
        @chunks = chunksArr.join("\n")
        for command in commands
            [cmd, args...] = command.split(/\s+/)
            @emit "cmd", cmd, args


class Control extends EventEmitter
    constructor: (@options = {}) ->
        @options.exitOnDisconnect ?= true
        @options.idleTime = 30000
        @idleTimeout = undefined
        @_server = undefined
        @_sockFile = undefined
        @_connections = []

    start: (callback) ->
        return callback new Error "already started" if @_server?
        @_server = net.createServer()
        @idleTimeout = setTimeout =>
            @stop()
        , @options.idleTime
        @_server.on "listening", =>
            callback?(null, @_sockFile)

        @_server.on "error", (err) =>
            # if err?.code is "EADDRINUSE"
            #     return @start(callback)
            callback?(err)

        @_server.on "connection", (socket) =>
            sock = new Sock socket
            @_connections.push sock
            sock.on "cmd", (cmd, args) =>
                @emit "cmd", socket, cmd, args
                @emit "cmd-#{cmd}", socket, args
            socket.on "close", =>
                @stop()

        @_sockFile = "/tmp/steadycontrol.#{process.pid}.sock"
        #path.join(process.cwd(), ["steadycontrol", Date.now()+"", Math.random().toString(16).slice(2), "sock"].join("."))
        @_server.listen(@_sockFile)

    stop: (callback) ->
        return if not @_server?
        try @_server.close()
        for c in @_connections
            c._socket?.destroy()
        @_connections = []
        @_server = undefined
        clearTimeout(@idleTimeout)


module.exports = new Control()