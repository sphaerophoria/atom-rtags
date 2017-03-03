const lazyreq = require('lazy-req').proxy(require)
const n_util = lazyreq('./util.js')

module.exports.OpenFileTracker = class OpenFileTracker {
    constructor(rcExecutor) {
        this.rcExecutor = rcExecutor;
        this.recentlyViewedItems = [];
        atom.workspace.onDidChangeActivePaneItem(this.updateRecentlyViewedItems.bind(this));
    }

    destroy() {
        this.recentlyViewedItems = null;
    }

    updateRecentlyViewedItems(item) {
        if (!item || !item.getPath || !n_util.matched_scope(item)) {
            return;
        }

        let path = item.getPath();
        let idx = this.recentlyViewedItems.indexOf(path);
        if (idx > -1) {
            this.recentlyViewedItems.splice(idx, 1);
        }
        this.recentlyViewedItems.unshift(path);

        const maxNumFiles = 5;
        if (this.recentlyViewedItems.length > maxNumFiles) {
            this.recentlyViewedItems.splice(maxNumFiles, this.recentlyViewedItems.length - maxNumFiles)
        }
        this.rcExecutor.set_buffers(this.recentlyViewedItems)
        .then(() => {
            // Diagnostics don't appear for files we haven't recently touched.
            // This allows us to get updated diagnostics when we go to look at
            // the file.
            this.rcExecutor.diagnose(item.getPath());
        })
        .catch((error) => { atom.notifications.addError(error); });
    }
}
