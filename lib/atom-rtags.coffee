{CompositeDisposable, Notifictaion} = require 'atom'
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
    openResultsWindowLocation:
      type: 'string'
      default: 'tab'
      enum: [
          {value: 'tab', description: 'Opens results in a new tab'}
          {value: 'rightPane', description: 'Opens results in a pane to the right'}
          {value: 'downPane', description: 'Opens results in a pane below current'}
      ]
    rdmCommand:
      type: 'string'
      default: ''
      description: 'Command to run to start the rdm server. If empty rdm server will not be autospawned, and should be started manually.'

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
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags:find_virtuals_at_point': => @find_virtuals_at_point()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags:location_stack_forward': => @location_stack_forward()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags:location_stack_back': => @location_stack_back()
    @location = {index:0, stack:[]}

  deactivate: ->
    AtomRtagsReferencesView.model = null
    @referencesModel = null
    @subscriptions?.dispose()
    @subscriptions = null
    @location = null

  find_symbol_at_point: ->
    try
      active_editor = atom.workspace.getActiveTextEditor()
      return if not active_editor
      return if not matched_scope(active_editor)
      @location_stack_push()
      [uri, r, c] = rtags.find_symbol_at_point active_editor.getPath(), active_editor.getCursorBufferPosition()
      atom.workspace.open uri, {'initialLine': r, 'initialColumn':c}
    catch err
      atom.notifications.addError err

  find_references_at_point: ->
    try
      active_editor = atom.workspace.getActiveTextEditor()
      return if not active_editor
      return if not matched_scope(active_editor)
      @location_stack_push()
      res = rtags.find_references_at_point active_editor.getPath(), active_editor.getCursorBufferPosition()
      @display_results_in_references(res)
    catch err
      atom.notifications.addError err

  find_virtuals_at_point: ->
    try
      active_editor = atom.workspace.getActiveTextEditor()
      return if not active_editor
      return if not matched_scope(active_editor)
      @location_stack_push()
      res = rtags.find_virtuals_at_point active_editor.getPath(), active_editor.getCursorBufferPosition()
      @display_results_in_references(res)
    catch err
      atom.notifications.addError err

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
      @location_stack_jump -2
    else
      @location_stack_jump -1

  location_stack_push: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    @location.stack.length = @location.index
    @location.stack.push [active_editor.getPath(), active_editor.getCursorBufferPosition()]
    @location.index = @location.stack.length

  display_results_in_references: (res) ->
    if res.matchCount == 1
      for uri, v of res.res
        atom.workspace.open uri, {'initialLine': v[0], 'initialColumn':v[1]}
    options = {searchAllPanes: true}
    switch atom.config.get('atom-rtags.openResultsWindowLocation')
        when 'tab' then null
        when 'rightPane' then options.split = 'right'
        when 'downPane' then options.split = 'down'
        else null
    @referencesModel.setModel res
    atom.workspace.open AtomRtagsReferencesView.URI, options
