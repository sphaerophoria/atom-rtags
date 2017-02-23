var child_process = require('child_process')

process.on('message', (m) => {
  try {
    var output = child_process.execSync(m.cmd, {input: m.input, encoding: 'utf8'})
    process.send({ stdout: output, error: 0, id: m.id});
  }
  catch (e) {
    process.send({ stdout: e.stdout, error: e.status, id: m.id});
  }
});
