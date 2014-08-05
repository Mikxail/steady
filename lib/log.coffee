slice = Array::slice
splice = Array::splice

console._pclusterOptions = {}

module.exports = (options) ->
    console._pclusterOptions = options ? {}

_args = ->
    prefix = console._pclusterOptions.prefix
    pid = process.pid
    ["[#{prefix}##{pid}]"].concat( slice.call arguments, 0 )

for f in ['log', 'warn', 'error', 'info']
    do (f) ->
        fn = console[f]
        console[f] = ->
            if console._pclusterTrace or console._pclusterOptions.always
                prefix = console._pclusterOptions.prefix or ""
                pid = process.pid
                splice.call arguments, 0, 0, "[#{prefix}##{pid}]"
            console._pclusterTrace = false
            fn.apply this, arguments

getter = ->
    @_pclusterTrace = true
    @

console.__defineGetter__ 'p', getter





