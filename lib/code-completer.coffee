{Point} = require 'atom'
rtags = require './rtags'

getType = (signature) ->
  ret = signature.split("(")[0]
  ret = ret.trim()
  splitIdx = ret.lastIndexOf(" ")
  ret = ret[..splitIdx-1]
  ret

createSnippetWithArgs = (completion, signature) ->
  sig_args = signature.split("(")
  sig = sig_args[0]
  args = sig_args[1]?.split(")")[0].split(",")

  if !args
    return completion
  if args?.length == 0
    return completion

  completion += '('
  i = 1
  for arg in args
    completion += "${#{i}:#{arg}},"
    i++
  # Truncate last comma
  completion = completion[..completion?.length-2]
  completion += ')'

  return completion

rtagsToCompletionType = (type) ->
  if type.includes("Constant") or type.includes("macro definition")
    return 'constant'
  else if type.includes("Function") or type.includes("Method") or type.includes("Constructor")
    return 'function'
  else if type.includes("VarDecl") or type.includes("FieldDecl")
    return 'variable'
  else if type.includes("ClassDecl") or type.includes("StructDecl") or type.includes("ClassTemplate")
    return 'type'

  return null

convertCompletion = (completionLine) ->
  # Looks like the format is (note the two spaces at the end)
  # <completion> <signature> <type>  <parent>

  completionLine = completionLine.trim()
  if completionLine == "macro definition"
    return null
  if completionLine?.length == 0
    return null
  splitIdx = completionLine.indexOf(' ');
  completion = completionLine[0..splitIdx-1]
  completionLine = completionLine[splitIdx+1..]

  # Parent exists if the last space is preceded by another space
  splitIdx = completionLine.lastIndexOf(' ')
  splitIdxTwo = completionLine.lastIndexOf(' ', splitIdx-1)
  parent = null
  if splitIdx == splitIdxTwo + 1
    parent = completionLine[splitIdx+1..]
    completionLine = completionLine[..splitIdxTwo-1]

  # Have to handle edge case where type is multi-word string macro definition
  macroDefStr = "macro definition"
  type = null
  if completionLine[completionLine?.length-macroDefStr?.length..] == macroDefStr
    type = macroDefStr
    completionLine = completionLine[..completionLine?.length-macroDefStr?.length-2]
  else
    splitIdx = completionLine.lastIndexOf(' ')
    type = completionLine[splitIdx+1..]
  signature = completionLine[..splitIdx]

  newType = rtagsToCompletionType(type)

  completion = createSnippetWithArgs(completion, signature)

  if !completion
    return null

  item = {"snippet": completion}

  # Macros repeat their own names as their types... Gross!
  if type != macroDefStr
    item["leftLabel"] = getType(signature)

  if newType
    item["type"] = newType
  item["rightLabel"] = type

  item

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
      .then((out) ->
        ret = []
        # TODO: This is terrible to read
        for line in out.split "\n"
          completion = convertCompletion(line)
          if completion
            ret.push(completion)
        @baseCompletions = ret
        @baseCompletions
      , (err) -> [])

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
