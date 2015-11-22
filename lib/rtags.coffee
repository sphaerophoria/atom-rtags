child_process = require 'child_process'

fn_loc = (fn, loc) ->
  fn + ':' + (loc.row+1) + ':' + (loc.column+1)

rc_exec =  (opt, stdin) ->
  rc_cmd = atom.config.get 'atom-rtags.rcCommand'
  cmd = rc_cmd + ' --no-color ' + opt.join(' ')
  #console.log 'exec ' + cmd
  out = child_process.execSync cmd
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
      res, pathCount, matchCount, symbolName:info.SymbolName,
      symbolLength:Number(info.SymbolLength)
    }

  get_symbol_info: (fn, loc) ->
    out = rc_exec ['-U', fn_loc(fn, loc)]
    res = {}
    for line in out.split "\n"
      [k, v] = line.split ":"
      res[k] = v
    res
