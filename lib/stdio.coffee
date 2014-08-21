Stream  = require 'stream'
fs      = require 'fs'
DevNull = require './dev-null'


module.exports = stdio = {}

stdio.defaultStdout = process.stdout
stdio.defaultStderr = process.stderr

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

    if stdout instanceof Stream
        oldStdout = process.stdout
        process.__defineGetter__ "stdout", () -> stdout
        if not oldStdout._isStdio
            oldStdout.end?()
            oldStdout = undefined

    if stderr instanceof Stream
        oldStderr = process.stderr
        process.__defineGetter__ "stderr", () -> stderr
        if not oldStderr._isStdio
            oldStderr.end?()
            oldStderr = undefined

    if console.Console?
        process.console = console.Console process.stdout, process.stderr
