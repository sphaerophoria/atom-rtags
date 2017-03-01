var child_process = require('child_process')

process.on('message', (m) => {
  try {
    var child = child_process.spawn(m.cmd, m.args, {encoding: 'utf8'})

    var stdout = ""

    var handleFinished = (code, signal) => {
      process.send({m: m, stdout: stdout, error: code, id: m.id});
    };

    child.stdout.on('data', (data) => {
      stdout += data;
    });

    child.on('exit', handleFinished);

    if (m.input) {
      child.stdin.write(m.input);
    }
  }
  catch (e) {
    process.send({ stdout: e.stdout, error: e.status, id: m.id});
  }
});
