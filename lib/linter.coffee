{TextBuffer} = require 'atom'

module.exports.RtagsLinter =
  class RtagsLinter
    constructor: (rcExecutor) ->
      @rcExecutor = rcExecutor
      @enableCodeLinting = atom.config.get('atom-rtags-plus.codeLinting')
      @linter = null
      @diagnostics = null
      @current_linter_messages = {}
      if !@rcExecutor.rdmStarted
        @rcExecutor.on('rdmStarted', @updateLinterStatus.bind(@, atom.config.get('atom-rtags-plus.codeLinting')))
      else
        @updateLinterStatus(atom.config.get('atom-rtags-plus.codeLinting'))
      atom.config.observe('atom-rtags-plus.codeLinting', (enable) => @updateLinterStatus(enable))

    destroy: ->
      @stopLinting()

    registerLinter: (indieRegistry) ->
      @linter = indieRegistry.register {name: "Rtags Linter"}

    updateLinterStatus: (enable) ->
      if enable and @rcExecutor.rdmStarted
        @startLinting()
      else
        @stopLinting()

    startLinting: ->
      if !@diagnostics
        @diagnostics = @rcExecutor.rc_diagnostics_start(@updateLinter)

    stopLinting: ->
      @diagnostics?.kill()
      @current_linter_messages = {}
      @diagnostics = null
      @linter?.setMessages([])

    updateLinter: (data) =>
      # Parse data into linter strings
      # Linter only updates one file at a time... so every time we set messages we have to aggregate all our previous linted files
      res = []
      for file in data?.checkstyle?.file
        @current_linter_messages[file.$.name] = []
        fileBuf = new TextBuffer({filePath: file.$.name})
        fileBuf.loadSync()
        for error in file.error
          if error.$.severity != "skipped" and error.$.severity != "none"
            errorLine = parseInt(error.$.line, 10) - 1
            errorCol = parseInt(error.$.column, 10) - 1
            start_point = [errorLine, errorCol]
            end_point = [errorLine]
            filePath = file.$.name

            lineStr = fileBuf.lineForRow(errorLine)
            lineStr = lineStr[errorCol..]
            re = /^[&*]*[a-zA-Z0-9_]*/
            underlineStr = re.exec(lineStr)[0]
            endCol = underlineStr.length + errorCol
            end_point.push(endCol);

            @current_linter_messages[filePath].push {
              type: error.$.severity,
              text: error.$.message,
              filePath: filePath,
              severity: error.$.severity,
              range: [start_point, end_point]
            }

      for k,v of @current_linter_messages
        for error in v
          res.push error

      @linter?.setMessages(res)
