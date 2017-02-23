var child_process = require('child_process');
var xml2js = require('xml2js');
var { Notification } = require('atom');

// Converts a filename, location to the form of filename:line:column
let fn_loc = (fn, loc) =>
  // Add 1 because we 0 index in atom
  fn + ':' + (loc.row+1) + ':' + (loc.column+1)
;

let rdm_start = function() {
  let rdm_cmd = atom.config.get('atom-rtags-plus.rdmCommand');
  if (rdm_cmd) {
    child_process.exec(rdm_cmd);
    return "Starting rdm... Please try again";
  } else {
    return "Please start rdm";
  }
};

// Start rc diagnostics. Called on startup used for linter
// TODO: handle clase where rdm isn't up yet
let rc_diagnostics_start = function(callback) {
  let rc_cmd = atom.config.get('atom-rtags-plus.rcCommand');
  let child = child_process.spawn(rc_cmd, ['--diagnostics']);
  child.stdout.on('data', function(data) {
    try {
      xml2js.parseString(data.toString(), (err, result) => callback(result));
    } catch (err) {
      console.log(err);
    }});
  return child;
};

// rc references outputs some information related to the function we searched for, extract this information
// to avoid a call to rc -U (get symbol info)
let extract_symbol_info_from_references = function(references) {
  for (let line of Array.from(references.split("\n"))) {
    let [fn, row, col, ...strline] = Array.from(line.split(":"));
    strline = strline.join(':');
    strline = strline.slice(col);
    return strline.slice(0, strline.search(/[^a-zA-Z0-9_]/));
  }
};

let extract_object_from_class_hierarchy_line = function(line) {
  let [name, fnloc] = Array.from(line.split('\t'));
  fnloc = fnloc.split(':');
  return { name, fnloc: fnloc.slice(0, 3), children: [] };
};

// Takes rc references output and sticks it into a dictionary for us
// This will be easier when I get around to fixing the rtags json output
let format_references = function(out) {
  let pathCount;
  let info = extract_symbol_info_from_references(out);
  let res = {};
  let matchCount = pathCount = 0;
  for (let line of Array.from(out.split("\n"))) {
    let parent_fn_loc, parent_fn_sig;
    let [fn, row, col, ...strline] = Array.from(line.split(":"));
    strline = strline.join(':');
    [strline, parent_fn_sig, parent_fn_loc] = Array.from(strline.split("\tfunction: "));
    let parent_details = null;
    if (parent_fn_loc) {
      let [parent_fn_file, parent_fn_line, parent_fn_col] = Array.from(parent_fn_loc.split(":"));
      parent_fn_loc = { row: parent_fn_line - 1, column: parent_fn_col - 1};
      parent_details = {
        signature:  parent_fn_sig,
        filename: parent_fn_file,
        location: parent_fn_loc
      };
    }

    if (fn && row && col) {
      if (res[fn] == null) {
        res[fn] = [];
        pathCount++;
      }
      res[fn].push([row-1, col-1, strline, parent_details]);
      matchCount++;
    }
  }
  return {
    res, pathCount, matchCount, symbolName:info,
    symbolLength:info.length
  };
};


module.exports.RcExecutor = class RcExecutor {
  constructor() {
    this.rc_worker = child_process.fork(__dirname + '/rc-worker.js');
    this.messageId = 0;
  }

  destroy() {
    this.rc_worker.kill('SIGTERM');
  }

  // Params:
  //  opt: command line arguments for rtags
  //  input: What to pipe to stdin. null if nothing
  rc_exec(opt, input) {
    if (input == null) { input = null; }
    let rc_cmd = atom.config.get('atom-rtags-plus.rcCommand');
    let cmd = rc_cmd + ' --no-color ' + opt.join(' ');
    return new Promise(function(resolve, reject) {
      var handleMessage = function(messageId, m) {
        if (m.id != messageId) {
          this.rc_worker.once('message', handleMessage);
          return;
        }
        messageId--;
        let stdout = m.stdout;
        if (!stdout) {
          stdout = ""
        }
        let error = m.error;
        if (error) {
          if (stdout.includes("Can't seem to connect to server")) {
            reject(rdm_start());
          }
          if (stdout.length === 0) {
            reject("No Results");
          }
          reject(stdout);
        }
        resolve(stdout);
      }.bind(this, this.messageId);
      this.rc_worker.once('message', handleMessage)
      this.rc_worker.send({cmd: cmd, input: input, id: this.messageId});
      this.messageId++;
    }.bind(this));
  }

  // Finds symbol at fn: filename, loc: location
  find_symbol_at_point(fn, loc) {
    let promise = this.rc_exec([`--current-file=${fn}`, '-f', fn_loc(fn, loc), '-K']);
    return promise.then(function(out) {
      let col, row;
      [fn, row, col] = Array.from(out.split(":"));
      return [fn, row-1, col-1];
    });
  }

  // Finds references at fn: filename, loc: locaitiopn
  // does not include declarations
  find_references_at_point(fn, loc) {
    let promise = this.rc_exec([`--current-file=${fn}`, '-r', fn_loc(fn, loc), '-K', '--containing-function-location', '--containing-function']);
    return promise.then(out => format_references(out));
  }

  // Finds references at fn: filename, loc: location
  // includes declarations
  find_all_references_at_point(fn, loc) {
    let promise = this.rc_exec([`--current-file=${fn}`, '-r', fn_loc(fn, loc), '-e', '-K']);
    return promise.then(out => format_references(out));
  }

  // Finds virtual overloads for function under curosor
  find_virtuals_at_point(fn, loc) {
    let promise = this.rc_exec([`--current-file=${fn}`, '-r', fn_loc(fn, loc), '-K', '-k']);
    return promise.then(out => format_references(out));
  }

  // Starts rc diagnostics
  rc_diagnostics_start(callback) {
    return rc_diagnostics_start(callback);
  }

  // This is the calldown for autocompletion. Sticks our current buffer into stdin and then gets results out of rtags
  rc_get_completions(fn, loc, current_content, prefix) {
    let promise;
    return promise = this.rc_exec([`--current-file=${fn}`, '-b', `--unsaved-file=${fn}:${current_content.length}`, '--code-complete-at', fn_loc(fn, loc), '--synchronous-completions', `--code-complete-prefix=${prefix}`], current_content);
  }

  find_symbols_by_keyword(keyword) {
    if (!keyword) {
      return Promise.reject("No Query");
    }
    let promise = this.rc_exec(['-z', '-K', '-F', keyword, '--wildcard-symbol-names']);
    return promise.then(out => format_references(out));
  }

  find_references_by_keyword(keyword) {
    if (!keyword) {
      return Promise.reject("No Query");
    }
    let promise = this.rc_exec(['-z', '-K', '-R', keyword, '--wildcard-symbol-names']);
    return promise.then(out => format_references(out));
  }

  reindex_current_file(fn) {
    return this.rc_exec(['-V', fn]);
  }

  get_refactor_locations(fn, loc) {
    let promise = this.rc_exec(['-z', '-e', '--rename', '-N', '-r', fn_loc(fn, loc), '-K']);
    // Group by file for easier use
    return promise.then(function(out) {
      let ret = [];
      for (let line of Array.from(out.split('\n'))) {
        let col, path;
        if (line === "") {
          continue;
        }
        [path, line, col] = Array.from(line.split(':'));
        if (ret[path] === undefined) {
          ret[path] = [];
        }
        ret[path].push({line, col});
      }
      return ret;
      });
  }

  get_subclasses(fn, loc) {
    let hierarchyTxt = this.rc_exec(['-z', '-K', '--class-hierarchy', fn_loc(fn, loc)]);
    let indentLevel = 1;

    let hierarchy = null;
    let foundSubclasses = false;
    for (let line of Array.from(hierarchyTxt.split('\n'))) {
      if ((line !== "Subclasses:") && (foundSubclasses === false)) {
        continue;
      } else if (line === "Subclasses:") {
        foundSubclasses = true;
        continue;
      }

      // Count leading spaces
      let numSpaces = 0;
      while (line[numSpaces] === " ") {
        numSpaces++;
      }
      // each indent is 2 spaces
      indentLevel = numSpaces / 2;

      if (indentLevel === 0) {
        continue;
      }

      if (indentLevel === 1) {
        line = line.slice(numSpaces);
        hierarchy = extract_object_from_class_hierarchy_line(line);
        continue;
      }

      let current = hierarchy;
      for (let i of Array.from(__range__(2, indentLevel, true).slice(1))) {
        current = current.children[current.children.length - 1];
      }
      line = line.slice(numSpaces);
      current.children.push(extract_object_from_class_hierarchy_line(line));
    }

    return hierarchy;
  }

  get_symbol_info(fn, loc) {
    let promise = this.rc_exec(['-z', '-K', '-U', fn_loc(fn, loc)]);
    return promise.then(function(out) {
      let ret = {};
      for (let line of Array.from(out.split('\n').slice(1))) {
        let splitIdx = line.indexOf(':');
        let k = line.slice(0, splitIdx-1 + 1 || undefined).trim();
        let v = line.slice(splitIdx+1).trim();
        ret[k] = v;
      }

      try {
        ret["ExtendedType"] = ret["Type"];
        ret["Type"] = ret["Type"].split("=>")[0].trim();
      } catch (error) {}
        // Do nothing

      return ret;
    });
  }
}
