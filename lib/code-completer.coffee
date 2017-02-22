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
  argPos = 1

  templateArgs = sig.split(completion)[1]
  if templateArgs
    templateArgsIdx = templateArgs.indexOf("<")
    if templateArgsIdx != -1
      templateArgs = templateArgs[templateArgsIdx+1..]
      templateArgsFinishIdx = templateArgs.lastIndexOf(">")
      templateArgs = templateArgs[..templateArgsFinishIdx - 1]
      templateArgs = templateArgs.split(",")
      completion += '<'
      for arg in templateArgs
        completion += "${#{argPos}:#{arg}},"
        argPos++
      completion = completion[..completion.length-2]
      completion += ">"


  if !args
    return completion
  if args.length == 0
    return completion

  completion += '('
  for arg in args
    completion += "${#{argPos}:#{arg}},"
    argPos++
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
  else
    if item["snippet"].includes("(")
      newType = "function"


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
    @initialPrefix = ""

  # On input autocompletion calls this function
  getSuggestions: ({editor, bufferPosition, scopeDescriptor, prefix, activatedManually}) ->
    # Check if we're actually enabled
    enableCodeCompletion = atom.config.get('atom-rtags-plus.codeCompletion')
    if !enableCodeCompletion
      return

    # This handles an edge case where spamming rtags with completion two times in a row (when typing ::) results in no completions
    if prefix == ":"
      return

    # This should come *before* newCompletionLocation is set. That way the next character will be resolved as part of
    # this set of completions
    while prefix[0] == "." or prefix[0] == ":"
      prefix = prefix[1..]

    newCompletionLocation = new Point
    newCompletionLocation.row = bufferPosition.row
    newCompletionLocation.column = bufferPosition.column - prefix.length
    bufferPosition.column -= 1

    # Intentionally after newCompletionLocation has been set. We don't want adding this space affecting our results
    # This is a fairly strange edge case. It looks like rtags doesn't like to give us results unless there's a space
    # in some cases (after :: or ->). This seems to resolve the issue. I don't think there's much danger here as any
    # "" prefix will be preceded by either whitespace or a special character which c/c++ should allow...
    if prefix == ""
      prefix = " "
      bufferPosition.column += 1

    if prefix[0..@initialPrefix.length] != @initialPrefix
      @initialPrefix = prefix
      @currentCompletionLocation = new Point

    if @currentCompletionLocation != null and @currentCompletionLocation.compare(newCompletionLocation)
      editorText = editor.getText()
      @currentCompletionLocation = newCompletionLocation
      # Asynchronously get results in a promise
      @baseCompletionsPromise = rtags.rc_get_completions editor.getPath(), newCompletionLocation, editorText, prefix
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
