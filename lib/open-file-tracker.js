

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
        if (item.getPath) {
            let path = item.getPath();
            let idx = this.recentlyViewedItems.indexOf(path);
            if (idx > -1) {
                this.recentlyViewedItems.splice(idx, 1);
            }
            this.recentlyViewedItems.unshift(path);
        }

        const maxNumFiles = 5;
        if (this.recentlyViewedItems.length > maxNumFiles) {
            this.recentlyViewedItems.splice(maxNumFiles, this.recentlyViewedItems.length - maxNumFiles)
        }
        this.rcExecutor.set_buffers(this.recentlyViewedItems)
        .catch((error) => { atom.notifications.addError(error); });
    }
}
