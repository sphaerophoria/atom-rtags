child_process = require 'child_process'
xml2js = require 'xml2js'
{Notification} = require 'atom'

# Converts a filename, location to the form of filename:line:column
fn_loc = (fn, loc) ->
  # Add 1 because we 0 index in atom
  fn + ':' + (loc.row+1) + ':' + (loc.column+1)

rdm_start = () ->
  rdm_cmd = atom.config.get 'atom-rtags-plus.rdmCommand'
  if rdm_cmd
    child_process.exec(rdm_cmd)
    return "Starting rdm... Please try again"
  else
    return "Please start rdm"

# Params:
#  opt: command line arguments for rtags
#  input: What to pipe to stdin. null if nothing
rc_exec =  (opt, input=null) ->
  rc_cmd = atom.config.get 'atom-rtags-plus.rcCommand'
  cmd = rc_cmd + ' --no-color ' + opt.join(' ')
  #console.log 'exec ' + cmd
  new Promise((resolve, reject) =>
    child = child_process.exec(cmd, (error, stdout, stderr) =>
      if (error)
        if stdout.includes("Can't seem to connect to server")
          reject(rdm_start())
        if stdout.length == 0
          reject("No Results")
        reject(stdout)
      resolve(stdout)
      )
    if input != null
      child.stdin.end(input)
    )

# Start rc diagnostics. Called on startup used for linter
# TODO: handle clase where rdm isn't up yet
rc_diagnostics_start = (callback) ->
  rc_cmd = atom.config.get 'atom-rtags-plus.rcCommand'
  child = child_process.spawn(rc_cmd, ['--diagnostics'])
  child.stdout.on('data', (data) ->
    try
      xml2js.parseString(data.toString(), (err, result) ->
        callback(result)
      )
    catch err
      console.log(err))
  child

# rc references outputs some information related to the function we searched for, extract this information
# to avoid a call to rc -U (get symbol info)
extract_symbol_info_from_references = (references) ->
  for line in references.split "\n"
    [fn, row, col, strline...] = line.split ":"
    strline = strline.join ':'
    strline = strline.slice col
    return strline.slice 0, strline.search(/[^a-zA-Z0-9_]/)

# Takes rc references output and sticks it into a dictionary for us
# This will be easier when I get around to fixing the rtags json output
format_references = (out) ->
  info = extract_symbol_info_from_references(out)
  res = {}
  matchCount = pathCount = 0
  for line in out.split "\n"
    [fn, row, col, strline...] = line.split ":"
    strline = strline.join ':'
    [strline, parent_fn_sig, parent_fn_loc] = strline.split "\tfunction: "
    parent_details = null
    if parent_fn_loc
      [parent_fn_file, parent_fn_line, parent_fn_col] = parent_fn_loc.split ":"
      parent_fn_loc = { row: parent_fn_line - 1, column: parent_fn_col - 1}
      parent_details = {
        signature:  parent_fn_sig
        filename: parent_fn_file
        location: parent_fn_loc
      }

    if fn and row and col
      if not res[fn]?
        res[fn] = []
        pathCount++
      res[fn].push [row-1, col-1, strline, parent_details]
      matchCount++
  {
    res, pathCount, matchCount, symbolName:info,
    symbolLength:info.length
  }


module.exports =
  # Finds symbol at fn: filename, loc: location
  find_symbol_at_point: (fn, loc) ->
    promise = rc_exec ['--current-file='+fn, '-f', fn_loc(fn, loc), '-K']
    promise.then((out) ->
      [fn, row, col] = out.split ":"
      return [fn, row-1, col-1]
    )

  # Finds references at fn: filename, loc: locaitiopn
  # does not include declarations
  find_references_at_point: (fn, loc) ->
    promise = rc_exec ['--current-file='+fn, '-r', fn_loc(fn, loc), '-K', '--containing-function-location', '--containing-function']
    promise.then((out) -> format_references(out))

  # Finds references at fn: filename, loc: location
  # includes declarations
  find_all_references_at_point: (fn, loc) ->
    promise = rc_exec ['--current-file='+fn, '-r', fn_loc(fn, loc), '-e', '-K']
    promise.then((out) -> format_references(out))

  # Finds virtual overloads for function under curosor
  find_virtuals_at_point: (fn, loc) ->
    promise = rc_exec ['--current-file='+fn, '-r', fn_loc(fn, loc), '-K', '-k']
    promise.then((out) -> format_references(out))

  # Starts rc diagnostics
  rc_diagnostics_start: (callback) ->
    rc_diagnostics_start(callback)

  # This is the calldown for autocompletion. Sticks our current buffer into stdin and then gets results out of rtags
  rc_get_completions: (fn, loc, current_content, prefix) ->
    promise = rc_exec ['--current-file='+fn, '-b', '--unsaved-file='+fn+':'+current_content.length, '--code-complete-at', fn_loc(fn, loc), '--synchronous-completions', '--code-complete-prefix='+prefix], current_content
    promise.then((out) ->
      ret = []
      # TODO: This is terrible to read
      for line in out.split "\n"
        sig_args = line.split("(")
        sig = sig_args[0]
        args = sig_args[1]?.split(")")[0].split(",")
        if args == undefined
          args = []

        if sig == ""
          continue
        segments = sig.split " "

        snippet = ""
        snippet += segments[1]
        if args.length > 0
          snippet += "("
        i = 1
        for arg in args
          snippet += "${#{i}:#{arg}}"
          i++
          if (i <= args.length)
            snippet+= ","

        if args.length > 0
          snippet += ")"

        item = {"snippet": snippet}

        if args.length > 0
          item.type = 'function'

        ret.push(item)
      ret
      )

  find_symbols_by_keyword: (keyword) ->
    if !keyword
      return Promise.reject("No Query")
    promise = rc_exec ['-z', '-K', '-F', keyword, '--wildcard-symbol-names']
    promise.then((out) -> format_references(out))

  find_references_by_keyword: (keyword) ->
    if !keyword
      return Promise.reject("No Query")
    promise = rc_exec ['-z', '-K', '-R', keyword, '--wildcard-symbol-names']
    promise.then((out) -> format_references(out))

  reindex_current_file: (fn) ->
    rc_exec ['-V', fn]

  get_refactor_locations: (fn, loc) ->
    promise = rc_exec ['-z', '-e', '--rename', '-N', '-r', fn_loc(fn, loc), '-K']
    # Group by file for easier use
    promise.then((out) ->
      ret = []
      for line in out.split('\n')
        if line == ""
          continue
        [path, line, col] = line.split(':')
        if ret[path] == undefined
          ret[path] = []
        ret[path].push({line: line, col: col})
      ret
      )
