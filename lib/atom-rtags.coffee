{CompositeDisposable} = require 'atom'
# {AtomRtagsReferencesModel, AtomRtagsReferencesView} = require './atom-rtags-references-view'
AtomRtagsReferencesModel = require './atom-rtags-model'
AtomRtagsReferencesView = require './view/results-pane'
rtags = require './rtags'

matched_scope = (editor) ->
  for s in ['source.cpp', 'source.c']
    return true if s in editor.getRootScopeDescriptor().scopes
  return false

module.exports = AtomRtags =
  config:
    rcCommand:
      type: 'string'
      default: 'rc'
    openFindReferencesResultsInRightPane:
      type: 'boolean'
      default: false
      description: 'Open the find references results in a split pane instead of a tab in the same pane.'

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
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags:location_stack_forward': => @location_stack_forward()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags:location_stack_back': => @location_stack_back()
    @location = {index:0, stack:[]}

  deactivate: ->
    AtomRtagsReferencesView.model = null
    @referencesModel = null
    @subscriptions?.dispose()
    @subscriptions = null

  find_symbol_at_point: ->
    active_editor = atom.workspace.getActiveTextEditor()
    if active_editor
      return if not matched_scope(active_editor)
      @location_stack_push()
      [uri, r, c] = rtags.find_symbol_at_point active_editor.getPath(), active_editor.getCursorBufferPosition()
      atom.workspace.open uri, {'initialLine': r, 'initialColumn':c}

  find_references_at_point: ->
    active_editor = atom.workspace.getActiveTextEditor()
    if active_editor
      return if not matched_scope(active_editor)
      @location_stack_push()
      res = rtags.find_references_at_point active_editor.getPath(), active_editor.getCursorBufferPosition()
      if res.matchCount == 1
        for uri, v of res.res
          atom.workspace.open uri, {'initialLine': v[0], 'initialColumn':v[1]}
      options = {searchAllPanes: true}
      options.split = 'right' if atom.config.get('atom-rtags.openFindReferencesResultsInRightPane')
      @referencesModel.setModel res
      atom.workspace.open AtomRtagsReferencesView.URI, options

  location_stack_jump: (howmuch) ->
    loc =  @location.stack[@location.index+howmuch]
    if loc
      atom.workspace.open loc[0], {'initialLine': loc[1].row, 'initialColumn':loc[1].column}
      @location.index += howmuch

  location_stack_forward: ->
    @location_stack_jump +1

  location_stack_back: ->
    if @location.stack.length == @location.index
      @location_stack_push()
    @location_stack_jump -1

  location_stack_push: ->
    active_editor = atom.workspace.getActiveTextEditor()
    if active_editor
      @location.stack.length = @location.index
      @location.stack.push [active_editor.getPath(), active_editor.getCursorBufferPosition()]
      @location.index = @location.stack.length
