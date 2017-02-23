{CompositeDisposable, Notifictaion} = require 'atom'
{$} = require 'space-pen'
util = require './util'

# {AtomRtagsReferencesModel, AtomRtagsReferencesView} = require './atom-rtags-references-view'
{RtagsReferencesTreePane, RtagsReferenceNode} = require './view/references-tree-view'
{RtagsRefactorConfirmationNode, RtagsRefactorConfirmationPane} = require './view/refactor-confirmation-view'
RtagsSearchView = require './view/rtags-search-view'
RtagsCodeCompleter = require './code-completer.coffee'
RtagsTooltip = require './view/tooltip.coffee'
{RtagsLinter} = require './linter.coffee'
{RcExecutor} = require './rtags'
child_process = require 'child_process'

matched_scope = (editor) ->
  util.matched_scope(editor)

module.exports = AtomRtags =
  config:
    rcCommand:
      type: 'string'
      default: 'rc'
    rdmCommand:
      type: 'string'
      default: ''
      description: 'Command to run to start the rdm server. If empty rdm server will not be autospawned, and should be started manually.'
    codeCompletion:
      type: 'boolean'
      default: 'true'
      description: 'Whether or not to suggest code completions (restart atom to apply)'
    codeLinting:
      type: 'boolean'
      default: 'true'
      description: 'Enable to show compile errors (restart atom to apply)'

  subscriptions: null

  activate: (state) ->
    apd = require "atom-package-deps"
    apd.install('atom-rtags-plus')

    @referencesView = new RtagsReferencesTreePane
    @searchView = new RtagsSearchView
    @rcExecutor = new RcExecutor
    @codeCompletionProvider = new RtagsCodeCompleter(@rcExecutor)
    @linter = new RtagsLinter(@rcExecutor)

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register commands
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-symbol-at-point': => @find_symbol_at_point()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-references-at-point': => @find_references_at_point()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-all-references-at-point': => @find_all_references_at_point()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-virtuals-at-point': => @find_virtuals_at_point()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-symbols-by-keyword': => @find_symbols_by_keyword()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-references-by-keyword': => @find_references_by_keyword()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:reindex-current-file': => @reindex_current_file()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:refactor-at-point': => @refactor_at_point()
    #@subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:get-subclasses': => @get_subclasses()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:get-symbol-info': => @get_symbol_info()

  deactivate: ->
    @subscriptions?.dispose()
    @subscriptions = null
    @linter.destroy()
    @rcExecutor.destroy()

  # Toplevel function for linting. Provides a callback for every time rtags diagnostics outputs data
  # On new data we update the linter with our newly received results.
  consumeLinter: (indieRegistry) ->
    @linter.registerLinter(indieRegistry)

  # This is our autocompletion function.
  provide: ->
    @codeCompletionProvider


  find_symbol_at_point: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not matched_scope(active_editor)
    @rcExecutor.find_symbol_at_point(active_editor.getPath(), active_editor.getCursorBufferPosition()).then(([uri,r,c]) ->
      if !uri
        return
      atom.workspace.open uri, {'initialLine': r, 'initialColumn':c}
    , (error) -> atom.notifications.addError(error)
    )

  find_references_at_point: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not matched_scope(active_editor)
    promise = @rcExecutor.find_references_at_point active_editor.getPath(), active_editor.getCursorBufferPosition()
    promise.then((out) =>
      @display_results_in_references(out)
    , (error) -> atom.notifications.addError(error))

  find_all_references_at_point: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not matched_scope(active_editor)
    @rcExecutor.find_all_references_at_point(active_editor.getPath(), active_editor.getCursorBufferPosition())
    .then((out) =>
      @display_results_in_references(out)
    , (err) -> atom.notifications.addError(err))

  find_virtuals_at_point: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not matched_scope(active_editor)
    @rcExecutor.find_virtuals_at_point(active_editor.getPath(), active_editor.getCursorBufferPosition()).then((out) =>
      @display_results_in_references(out)
    , (err) -> atom.notifications.addError(err))

  find_symbols_by_keyword: ->
    findSymbolCallback = (query) =>
      @rcExecutor.find_symbols_by_keyword(query).then((out) =>
        @display_results_in_references(out)
      , (err) -> atom.notifications.addError(err))

    @searchView.setSearchCallback(findSymbolCallback)
    @searchView.show()

  find_references_by_keyword: ->
    findReferencesCallback = (query) =>
      @rcExecutor.find_references_by_keyword(query).then((out) =>
        @display_results_in_references(out)
      , (err) -> atom.notifications.addError(err))

    @searchView.setSearchCallback(findReferencesCallback)
    @searchView.show()

  reindex_current_file: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not matched_scope(active_editor)
    @rcExecutor.reindex_current_file(active_editor.getPath())

  refactor_at_point: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not matched_scope(active_editor)
    refactorCallback = (replacement) =>
      @rcExecutor.get_refactor_locations(active_editor.getPath(), active_editor.getCursorBufferPosition())
      .then((paths) ->
        items = []
        confirmationPane = new RtagsRefactorConfirmationPane
        for path, refactorLines of paths
          items.push(new RtagsRefactorConfirmationNode({path: path, refactorLines: refactorLines, replacement: replacement}, 0, confirmationPane.referencesTree.redraw))
        confirmationPane.show()
        confirmationPane.referencesTree.setItems(items)
        )

    @searchView.setSearchCallback(refactorCallback)
    @searchView.show()

  display_results_in_references: (res) ->
    if res.matchCount == 1
      for uri, v of res.res
        atom.workspace.open uri, {'initialLine': v[0], 'initialColumn':v[1]}
    references = []
    @referencesView.referencesTree.setItems([])
    for path, refArray of res.res
      for ref in refArray
        references.push(new RtagsReferenceNode({ref: ref, path:path, rcExecutor: @rcExecutor}, 0, @referencesView.referencesTree.redraw))

    @referencesView.show()
    @referencesView.referencesTree.setItems(references)

  get_subclasses: ->
    try
      active_editor = atom.workspace.getActiveTextEditor()
      return if not active_editor
      return if not matched_scope(active_editor)
      res = @rcExecutor.get_subclasses active_editor.getPath(), active_editor.getCursorBufferPosition()
    catch err
      atom.notifications.addError err

  get_symbol_info: ->
    try
      active_editor = atom.workspace.getActiveTextEditor()
      return if not active_editor
      return if not matched_scope(active_editor)
      res = @rcExecutor.get_symbol_info active_editor.getPath(), active_editor.getCursorBufferPosition()
      res.then( (out) ->
        atom.notifications.addInfo(out.Type)
      )
    catch err
      atom.notifications.addError err
