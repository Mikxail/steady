Stream  = require 'stream'
fs      = require 'fs'
DevNull = require './dev-null'


module.exports = stdio = {}

stdio.reopen = (stdout, stderr = stderr) ->
    return if not stdout?

    if typeof stdout is "string"
        if stdout isnt 'ignore'
            stdout = fs.createWriteStream stdout, {flags: "a"}
        else
            stdout = DevNull()
    if typeof stderr is "string"
        if stderr isnt 'ignore'
            stderr = fs.createWriteStream stderr, {flags: "a"}
        else
            stderr = DevNull()

    if not stdout instanceof Stream
        return
    if not stderr instanceof Stream
        return

    process.__defineGetter__ "stdout", () -> stdout
    process.__defineGetter__ "stderr", () -> stderr

    if console.Console?
        process.console = console.Console process.stdout, process.stderr
