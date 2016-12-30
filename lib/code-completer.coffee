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
  suggestionPriority: 2

  constructor: ->
    @currentCompletionLocation = new Point

  # On input autocompletion calls this function
  getSuggestions: ({editor, bufferPosition, scopeDescriptor, prefix, activatedManually}) ->
    # Check if we're actually enabled
    enableCodeCompletion = atom.config.get('atom-rtags-plus.codeCompletion')
    if !enableCodeCompletion
      return

    newCompletionLocation = new Point
    newCompletionLocation.row = bufferPosition.row
    newCompletionLocation.column = bufferPosition.column - prefix.length

    if @currentCompletionLocation.compare(newCompletionLocation)
      editorText = editor.getText()
      @currentCompletionLocation = newCompletionLocation
    else
      editorText = null

    # Asynchronously get results in a promise
    new Promise (resolve) ->
      out = rtags.rc_get_completions editor.getPath(), editor.getCursorBufferPosition(), editorText, prefix
      console.log(out)
      resolve(out)
