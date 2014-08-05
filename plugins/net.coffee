exports.save = (handle) ->
    {}

exports.restore = (server, handle) ->
    server._handle.onconnection(handle._handle)
    handle