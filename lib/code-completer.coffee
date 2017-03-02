lazyreq = require('lazy-req').proxy(require)
n_atom = lazyreq('atom')
n_fuzzaldrin = lazyreq('fuzzaldrin-plus')

getType = (signature) ->
  ret = signature.split("(")[0]
  ret = ret.trim()
  splitIdx = ret.lastIndexOf(" ")
  if (splitIdx >= 0)
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

  # Only trim left side because we need to keep right side to detect parent
  completionLine = completionLine?.trimLeft()
  if completionLine?.trim() == "macro definition"
    return null
  if completionLine?.trim().length == 0
    return null
  splitIdx = completionLine.indexOf(' ');
  completion = completionLine[0..splitIdx-1]
  completionLine = completionLine[splitIdx+1..]

  # Parent exists if the last space is preceded by another space
  splitIdx = completionLine.lastIndexOf('  ')
  parent = completionLine[splitIdx+1..].trim()
  completionLine = completionLine[..splitIdx].trim()

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

  constructor: () ->
    @rcExecutor = null
    @currentCompletionLocation = null
    @baseCompletionsPromise = null
    @initialPrefix = ""
    @doFuzzyCompletion = false;

  setRcExecutor: (rcExecutor) ->
    @rcExecutor = rcExecutor

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

    newCompletionLocation = new n_atom.Point(bufferPosition.row, bufferPosition.column - prefix.length)

    if @currentCompletionLocation == null
      @currentCompletionLocation = new n_atom.Point

    if @currentCompletionLocation.compare(newCompletionLocation)

      @currentCompletionLocation = newCompletionLocation.copy()

      # Asynchronously get results in a promise
      @baseCompletionsPromise = @rcExecutor.rc_get_completions editor.getPath(), newCompletionLocation, editor.getText(), ""
      .then((out) ->
        ret = []
        for line in out.split "\n"
          completion = convertCompletion(line)
          if completion
            ret.push(completion)
        ret)
      .catch((err) ->
        console.error(err)
        [])

    return @baseCompletionsPromise.then((completions) =>
      if (prefix.length == 0)
        return completions;
      ret = []
      if @doFuzzyCompletion
        ret = n_fuzzaldrin.filter(completions, prefix, key: 'snippet')
      else
        for completion in completions
          if completion.snippet and completion.snippet[0..prefix.length - 1] == prefix
            ret.push(completion)

      for completion in ret
        completion.replacementPrefix = prefix;

      ret
    )
