assert = require('assert').ok
getopt = require 'posix-getopt'

class exports.Cmd
	constructor: ->
		@commands = []
		@options = {}
		@nOptions = {}
		@txtHelp = ""
		@optsHelp = []
		@


	cmd: (command, fn) ->
		parts = command.match /^([\w\s]+)(.*)$/
		assert parts, 'bad command'
		@commands.push
			command: parts[1].split(/\s+/).map((s) -> s.trim()).filter(Boolean)
			opts: (parts[2]+"").split(/\s+/).map((s) -> s.trim()).filter(Boolean)
			fn: fn


	opts: (opts) ->
		@options = opts
		for k, v of opts
			nk = if k.length > 1 then "--#{k}" else "-#{k}"
			assert not @nOptions[nk], "duplicate option #{nk}"
			@nOptions[nk] = {k, v}
			na = undefined
			if v.alias?
				na = if v.alias.length > 1 then "--#{v.alias}" else "-#{v.alias}"
				assert not @nOptions[na], "duplicate option #{na}"
				@nOptions[na] = {k, v}
			nStr = "#{nk}"
			if na?
				nStr += ", #{na}"
			@optsHelp.push "\t#{nStr}\t\t[default: #{v.default}]"

		return

	help: (@txtHelp) ->
		return


	start: ->
		@_onCommand()


	_isCommand: (argv, c) ->
		if (index = argv.indexOf(c.command[0])) isnt -1
			for idx in [1...c.command.length] by 1
				if argv[index+idx] isnt c.command[idx]
					return false
			cmdLength = c.command.length
			parts = []
			for idx in [0...c.opts.length] by 1
				if not (optParts = argv[index+cmdLength+idx]?.match(c.opts[idx]))
					return false
				else
					parts.push optParts.slice(1)
			return {parts: parts, index: index}
		return false


	_findCommand: (argv) ->
		for c in @commands
			if {parts, index} = @_isCommand argv, c
				return {c: c, parts: parts, index: index}
		return


	_parseOptions: (opts) ->
		retOpts = {}
		skipNext = false
		for opt, idx in opts
			if skipNext
				skipNext = false
				continue

			if @nOptions[opt]
				{k, v} = @nOptions[opt]
				if v.boolean
					retOpts[k] = true
				else
					retOpts[k] = opts[idx+1]
					skipNext = true
			else
				assert null, "unknow option #{opt}"

		for k, opt of @options
			if opt.default? and not retOpts[k]?
				retOpts[k] = opt.default

		return retOpts



	_onCommand: () ->
		argv = process.argv.slice(2)
		command = @_findCommand argv
		if not command?
			console.log @txtHelp
			if @optsHelp.length
				console.log ""
				console.log "Options"
				console.log @optsHelp.join("\n")
			return

		opts = argv.slice(0, command.index)
		options2 = argv.slice(command.index+1+command.parts.length)
		options = @_parseOptions opts

		command.c.fn.apply null, [options].concat(command.parts).concat([options2])



