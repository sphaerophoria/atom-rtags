child_process = require 'child_process'
xml2js = require 'xml2js'
{Notification} = require 'atom'

fn_loc = (fn, loc) ->
  fn + ':' + (loc.row+1) + ':' + (loc.column+1)

rdm_start = () ->
  rdm_cmd = atom.config.get 'atom-rtags.rdmCommand'
  if rdm_cmd
    child_process.exec rdm_cmd, (err, stdout, stderr) ->
      atom.notifications.addError "Rtags rdm server died", stdout, stderr

rc_exec =  (opt, retry=true, input=null) ->
  rc_cmd = atom.config.get 'atom-rtags.rcCommand'
  cmd = rc_cmd + ' --no-color ' + opt.join(' ')
  #console.log 'exec ' + cmd
  try
    if input == null
      out = child_process.execSync cmd
    else
      out = child_process.execSync cmd, {"input": input}
  catch err
    out = err.output.toString()
    if out.includes('Can\'t seem to connect to server')
      if retry
        @rdm_start
        return rc_exec opt, false
      else
        throw 'Rtags rdm server is not running.'
    if out.includes('Not indexed')
      throw 'This file is not indexed in Rtags.'
    if err.stdout.length == 0 and err.stderr.length == 0
      throw 'No results'
    if err.status == 1
      throw 'Undefined error while executing rc command\n\n'+ cmd + '\n\nOutput: ' + out
  return out.toString()

rc_diagnostics_start = (callback) ->
  rc_cmd = atom.config.get 'atom-rtags.rcCommand'
  child = child_process.spawn(rc_cmd, ['--diagnostics'])
  child.stdout.on('data', (data) ->
    xml2js.parseString(data.toString(), (err, result) ->
      callback(result)
    ))
  child

extract_symbol_info_from_references = (references) ->
  for line in references.split "\n"
    [fn, row, col, strline...] = line.split ":"
    strline = strline.join ':'
    strline = strline.slice col
    return strline.slice 0, strline.search(/[^a-zA-Z0-9_]/)

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
      parent_fn_loc = [parent_fn_line - 1, parent_fn_col - 1]
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
  find_symbol_at_point: (fn, loc) ->
    out = rc_exec ['--current-file='+fn, '-f', fn_loc(fn, loc), '-K']
    [fn, row, col] = out.split ":"
    return [fn, row-1, col-1]

  find_references_at_point: (fn, loc) ->
    out = rc_exec ['--current-file='+fn, '-r', fn_loc(fn, loc), '-K', '--containing-function-location', '--containing-function']
    format_references(out)

  find_all_references_at_point: (fn, loc) ->
    out = rc_exec ['--current-file='+fn, '-r', fn_loc(fn, loc), '-e', '-K']
    format_references(out)

  find_virtuals_at_point: (fn, loc) ->
    out = rc_exec ['--current-file='+fn, '-r', fn_loc(fn, loc), '-K', '-k']
    format_references(out)

  rc_diagnostics_start: (callback) ->
    rc_diagnostics_start(callback)

  rc_get_completions: (fn, loc, current_content, prefix) ->
    out = rc_exec ['--current-file='+fn, '-b', '--unsaved-file='+fn+':'+current_content.length, '--code-complete-at', fn_loc(fn, loc), '--synchronous-completions', '--code-complete-prefix='+prefix], true, current_content
    # TODO: Parse in form completion signiture(...) annotation parent
    ret = []
    for line in out.split "\n"
      segments = line.split " "
      if segments[0] != ""
        continue
      ret.push({ "text": segments[1]})
    ret

  get_symbol_info: (fn, loc) ->
    out = rc_exec ['-r', fn_loc(fn, loc)]
    for line in out.split "\n"
      [fn, row, col, strline...] = line.split ":"
      strline = strline.join ':'
      strline = strline.slice col
      return strline.slice 0, strline.search(/[^a-zA-Z0-9_]/)
