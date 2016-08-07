child_process = require 'child_process'
{Notification} = require 'atom'

fn_loc = (fn, loc) ->
  fn + ':' + (loc.row+1) + ':' + (loc.column+1)

rdm_start = () ->
  rdm_cmd = atom.config.get 'atom-rtags.rdmCommand'
  if rdm_cmd
    child_process.exec rdm_cmd, (err, stdout, stderr) ->
      atom.notifications.addError "Rtags rdm server died", stdout, stderr

rc_exec =  (opt, retry=true) ->
  rc_cmd = atom.config.get 'atom-rtags.rcCommand'
  cmd = rc_cmd + ' --no-color ' + opt.join(' ')
  #console.log 'exec ' + cmd
  try
    out = child_process.execSync cmd
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
    if err.status == 1
      throw 'Undefined error while executing rc command\n\n'+ cmd + '\n\nOutput: ' + out
  return out.toString()

module.exports =
  find_symbol_at_point: (fn, loc) ->
    out = rc_exec ['--current-file='+fn, '-f', fn_loc(fn, loc), '-K']
    [fn, row, col] = out.split ":"
    return [fn, row-1, col-1]

  find_references_at_point: (fn, loc) ->
    info = @get_symbol_info(fn, loc)
    out = rc_exec ['--current-file='+fn, '-r', fn_loc(fn, loc), '-e', '-K']
    res = {}
    matchCount = pathCount = 0
    for line in out.split "\n"
      [fn, row, col, strline...] = line.split ":"
      strline = strline.join ':'
      if fn and row and col
        if not res[fn]?
          res[fn] = []
          pathCount++
        res[fn].push [row-1, col-1, strline]
        matchCount++
    {
      res, pathCount, matchCount, symbolName:info,
      symbolLength:info.length
    }

  get_symbol_info: (fn, loc) ->
    out = rc_exec ['-r', fn_loc(fn, loc)]
    for line in out.split "\n"
      [fn, row, col, strline...] = line.split ":"
      strline = strline.join ':'
      strline = strline.slice col
      return strline.slice 0, strline.search(/[^a-zA-Z0-9_]/)
