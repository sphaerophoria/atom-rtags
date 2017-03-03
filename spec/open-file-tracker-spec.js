const {RcExecutor} = require('../lib/rtags.js');
const {OpenFileTracker} = require('../lib/open-file-tracker.js');

describe("Open file tracker", () => {
    var rcExecutor = new RcExecutor();
    rcExecutor.start_rc_worker();
    var finished = false;
    var openFileTracker;

    beforeEach(function() {
        atom.config.set('atom-rtags-plus.rcCommand', 'rc');
        finished = false;
        openFileTracker = new OpenFileTracker(rcExecutor);
    });

    it("should inform rtags of the previously opened files", () => {
        //TODO
    });

    it("should only inform rtags of the previously n opened files", () => {
        //TODO
    });

    it("should only inform rtags of c/c++ files", () => {
        //TODO
    });
});
