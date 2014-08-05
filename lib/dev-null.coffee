util        = require 'util'
{Writable}  = require('stream')
{Stream}    = require('stream')

DevNull = (opts = {}) ->
    if not (@ instanceof DevNull)
        return new DevNull opts
    (Writable ? Stream).call @, opts

# node v0.10
if Writable?
    util.inherits DevNull, Writable

    DevNull::_write = (chunk, encoding, callback)->
        process.nextTick callback
# node v0.8
else
    util.inherits DevNull, Stream

    DevNull::write = (chunk, encoding) ->
        return true

module.exports = DevNull
