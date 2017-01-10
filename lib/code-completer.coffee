{Point} = require 'atom'

rtags = require './rtags'
module.exports =
class RtagsCodeCompleter
  # Use for the following types
  selector: '.source.cpp, .source.c, .source.cc, .source.h, .source.hpp'
  # Put at the top of the list
  includionPriority: 1
  # Scrap all those other suggestions, ours are great
  excludeLowerPriority: true
  suggestionPriority: 1

  constructor: ->
    @currentCompletionLocation = new Point
    @currentCompletionLocation = null
    @baseCompletionsPromise = null
    @baseCompletions = []

  # On input autocompletion calls this function
  getSuggestions: ({editor, bufferPosition, scopeDescriptor, prefix, activatedManually}) ->
    # Check if we're actually enabled
    enableCodeCompletion = atom.config.get('atom-rtags-plus.codeCompletion')
    if !enableCodeCompletion
      return

    newCompletionLocation = new Point
    newCompletionLocation.row = bufferPosition.row
    newCompletionLocation.column = bufferPosition.column - prefix.length
    bufferPosition.column -= 1

    if prefix[0] != @initialPrefix
      @initialPrefix = prefix[0]
      @currentCompletionLocation = new Point

    if prefix == "."
      prefix = ""
      bufferPosition.column += 1

    if @currentCompletionLocation != null and @currentCompletionLocation.compare(newCompletionLocation)
      editorText = editor.getText()
      @currentCompletionLocation = newCompletionLocation
      # Asynchronously get results in a promise
      @baseCompletionsPromise = rtags.rc_get_completions editor.getPath(), bufferPosition, editorText, prefix
      @baseCompletionsPromise.then((data) ->
        @baseCompletions = data
        @baseCompletions)
      return @baseCompletionsPromise
    else
      return @baseCompletionsPromise.then(() ->
        ret = []
        for completion in @baseCompletions
          if completion.snippet and completion.snippet[0..prefix.length - 1] == prefix
            completion.replacementPrefix = prefix
            ret.push(completion)
        ret
      )
