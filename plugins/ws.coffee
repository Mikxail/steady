_ = require 'underscore'
WebSocket = require 'ws/lib/WebSocket'
netPlugin = require './net'

exports.save = (handle) ->
    _.extend netPlugin.save(handle), _.pick(handle, "protocolVersion", "protocol", "upgradeReq")

exports.restore = (wss, handle, data, opts = {emitConnection: true}) ->
    server = wss._server
    netPlugin.restore(server, handle)
    upgradeHead = ""
    client = new WebSocket([data.upgradeReq, handle, upgradeHead], {
      protocolVersion: data.protocolVersion,
      protocol: data.protocol
    });
    if opts.emitConnection
        wss.emit('connection'+data.upgradeReq.url, client)
        wss.emit('connection', client)
    if opts.emitRestore
        wss.emit('restore'+data.upgradeReq.url, client)
        wss.emit('restore', client)
