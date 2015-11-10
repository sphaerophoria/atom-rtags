{CompositeDisposable} = require 'atom'
# {AtomRtagsReferencesModel, AtomRtagsReferencesView} = require './atom-rtags-references-view'
AtomRtagsReferencesModel = require './atom-rtags-model'
AtomRtagsReferencesView = require './view/results-pane'
rtags = require './rtags'

module.exports = AtomRtags =
  subscriptions: null

  activate: (state) ->
    atom.workspace.addOpener (filePath) ->
      new AtomRtagsReferencesView() if filePath is AtomRtagsReferencesView.URI

    @referencesModel = new AtomRtagsReferencesModel
    AtomRtagsReferencesView.model = @referencesModel

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register commands
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags:find_symbol_at_point': => @find_symbol_at_point()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags:find_references_at_point': => @find_references_at_point()

  deactivate: ->
    AtomRtagsReferencesView.model = null
    @referencesModel = null
    @subscriptions?.dispose()
    @subscriptions = null

  find_symbol_at_point: ->
    active_editor = atom.workspace.getActiveTextEditor()
    if active_editor
      [uri, r, c] = rtags.find_symbol_at_point active_editor.getPath(), active_editor.getCursorBufferPosition()
      atom.workspace.open uri, {'initialLine': r, 'initialColumn':c}

  find_references_at_point: ->
    active_editor = atom.workspace.getActiveTextEditor()
    if active_editor
      res = rtags.find_references_at_point active_editor.getPath(), active_editor.getCursorBufferPosition()
      if res.matchCount == 1
        for uri, v of res.res
          atom.workspace.open uri, {'initialLine': v[0], 'initialColumn':v[1]}
      options = {searchAllPanes: true, split:'right'}
      @referencesModel.setModel res
      atom.workspace.open AtomRtagsReferencesView.URI, options
