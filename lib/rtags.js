var child_process = require('child_process');
var { Point, Notification, Range } = require('atom');
var util = require('./util');
const EventEmitter = require('events');

// Converts a filename, location to the form of filename:line:column
let fn_loc = (fn, loc) =>
  // Add 1 because we 0 index in atom
  fn + ':' + (loc.row+1) + ':' + (loc.column+1)
;

// Start rc diagnostics. Called on startup used for linter
// TODO: handle clase where rdm isn't up yet
let rc_diagnostics_start = function(callback) {
  let rc_cmd = atom.config.get('atom-rtags-plus.rcCommand');
  let child = child_process.spawn(rc_cmd, ['--diagnostics']);
  child.stdout.on('data', function(data) {
    let xml2js = require('xml2js');
    try {
      xml2js.parseString(data.toString(), (err, result) => callback(result));
    } catch (err) {
      console.error(err);
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


module.exports.RcExecutor = class RcExecutor extends EventEmitter {
  constructor() {
    super();
    this.rc_worker = null;
    this.messageId = 0;
    this.rdmStarted = false;
    let startup = () => {
        this.start_rc_worker();
        this.maybe_start_rdm();
    }
    let bStarted = false;
    for (let editor of atom.workspace.getTextEditors()) {
      if (util.matched_scope(editor)) {
        startup();
        bStarted = true;
      }
    }
    if (!bStarted)
    {
      this.initSubscription = atom.workspace.onDidAddTextEditor((e) => {
        if (util.matched_scope(e.textEditor)) {
          startup();
          this.initSubscription.dispose();
        }
      })
    }
  }

  destroy() {
    if (this.rc_worker) {
      this.rc_worker.kill('SIGTERM');
    }
  }

  start_rc_worker() {
    if (!this.rc_worker) {
      this.rc_worker = child_process.fork(__dirname + '/rc-worker.js');
    }
  }

  maybe_start_rdm() {
    if (this.rdmStarted) {
      return;
    }

    let markRdmStarted = () => {
      this.rdmStarted = true;
      this.emit('rdmStarted')
    }

    try {
      child_process.execSync('rc -w');
      markRdmStarted();
    }
    catch (e) {
      let rdm_cmd = atom.config.get('atom-rtags-plus.rdmCommand');
      if (rdm_cmd) {
        child_process.exec(rdm_cmd);
        markRdmStarted();
        return "Starting rdm... Please try again";
      } else {
        return "Please start rdm";
      }
    }
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
        let stdout = m.stdout;
        if (!stdout) {
          stdout = ""
        }
        let error = m.error;
        if (error) {
          if (stdout.includes("Can't seem to connect to server")) {
            this.rdmStarted = false;
            reject(this.maybe_start_rdm());
          }
          if (stdout.length === 0) {
            reject("No Results");
          }
          reject(stdout);
        }
        this.rdmStarted = true;
        resolve(stdout);
      }.bind(this, this.messageId);
      this.rc_worker.once('message', handleMessage)
      this.rc_worker.send({cmd: cmd, input: input, id: this.messageId});
      this.messageId = (this.messageId + 1) % ((1<<16) - 1);
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
    return this.rc_exec([`--current-file=${fn}`, '-b', `--unsaved-file=${fn}:${current_content.length}`, '--code-complete-at', fn_loc(fn, loc), '--synchronous-completions', `--code-complete-prefix=${prefix}`], current_content)
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
    let promise = this.rc_exec(['-z', '-K', '-U', fn_loc(fn, loc), '--no-context', '--json']);
    return promise.then(function(out) {
      let ret = JSON.parse(out);

      try {
        ret.extendedType = ret.type;
        ret.type = ret.type.split(" => ")[0].trim()
      } catch (error) {}

      ret.startLine -= 1;
      ret.startColumn -= 1;
      ret.endLine -= 1;
      ret.endColumn -= 1;

      // Parse location
      let [fn, row, column] = ret.location.split(':')
      ret.location = {
        filename: fn,
        row: parseInt(row) - 1,
        column: parseInt(column) - 1
      };

      return ret;
    });
  }

  get_tokens(fn) {
    let promise = this.rc_exec(['--tokens', fn, '-K']);
    let rootPromise = this.rc_exec(['--find-project-root', fn, '-K'])
      .then((out) => {
        let path = out.split(' => ')[1];
        // [path]\n
        return path.slice(1, path.length - 2);
      })
    return Promise.all([promise, rootPromise]).then(function([out, root]) {
      // Grouped in 3 line chuncks where the third line could be multiline...
      // Hopefully the term "Location: <fn>" is never used ever....
      // Unfortunately rc just ignores the absolute path flag so we have to figure
      // out the path relative to the root of the project

      let relFn = fn.split(root)[1];
      let items = out.split('Location: ' + relFn);
      items.shift();

      // format here is
      // Location: <fn>:line:col: Offset: <offset> Length: <length> Kind: <kind>
      let parsedItems = [];
      for (let i = 0; i < items.length; ++i)
      {
        parsedItems[i] = {}

        let item = items[i];

        // First item sometimes is empty
        if (item == "") {
          continue;
        }

        // If someone makes a filename containing any of the following this will break.
        let tmp = item.split('\nSpelling:\n')
        item = tmp[0];
        // Strip the last \n
        let tmpSpelling = tmp[1].substring(0, tmp[1].length - 1);
        // This sucks, they insert a leading space on every line
        parsedItems[i].spelling = ""
        for (let line of tmpSpelling.split('\n'))
        {
          parsedItems[i].spelling += line.substring(1, line.length);
        }
        tmp = item.split(' Kind: ');
        item = tmp[0];
        parsedItems[i].kind = tmp[1];
        tmp = item.split(' Length: ');
        item = tmp[0];
        parsedItems[i].length = tmp[1];
        tmp = item.split(' Offset: ');
        item = tmp[0];
        parsedItems[i].offset = tmp[1];
        parsedItems[i].location = new Point;
        [,parsedItems[i].location.row,,parsedItems[i].location.column,] = tmp[0].split(':');
      }
      return parsedItems;
    });
  }

  set_buffers(filenames) {
    let nameStr = "\"";
    for (let filename of filenames) {
      nameStr += filename + ";"
    }
    nameStr += "\"";

    // Sending ";" seems to clear the list
    return this.rc_exec(['--set-buffers', '";"']).then(() => {
      this.rc_exec(['--set-buffers', nameStr])})
  }
}
