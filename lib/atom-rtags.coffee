lazyreq = require('lazy-req').proxy(require)

n_referencesTreeView = lazyreq('./view/references-tree-view.coffee')
n_rtagsSearchView = lazyreq('./view/rtags-search-view.coffee')
RtagsCodeCompleter = require('./code-completer.coffee')
n_rtagsHyperClicker = lazyreq('./rtags-hyperclicker.js')
n_util = lazyreq('./util.js')

updateKeybindingMode = (value) ->
  workspace = document.getElementsByTagName("atom-workspace")[0]
  workspace.classList.remove('atom-rtags-plus-eclipse')
  workspace.classList.remove('atom-rtags-plus-qtcreator')
  workspace.classList.remove('atom-rtags-plus-vim')
  switch value
    when 0 then workspace.classList.add('atom-rtags-plus-eclipse')
    when 1 then workspace.classList.add('atom-rtags-plus-qtcreator')
    when 2 then workspace.classList.add('atom-rtags-plus-vim')

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
    fuzzyCodeCompletion:
      type: 'boolean'
      default: 'true'
      description: 'When code completion is enabled, whether to fuzzy match the results'
    codeLinting:
      type: 'boolean'
      default: 'true'
      description: 'Enable to show compile errors (restart atom to apply)'
    keybindingStyle:
      type: 'integer'
      description: "Keybinding style"
      default: 3
      enum: [
        {value: 0, description: 'Eclipse style keymap'}
        {value: 1, description: 'QT Creator style keymap'}
        {value: 2, description: 'Vim style keymap'}
        {value: 3, description: 'Define your own'}
      ]

  subscriptions: null

  activate: (state) ->
    @codeCompletionProvider = new RtagsCodeCompleter()
    @hyperclickProvider = new n_rtagsHyperClicker.RtagsHyperclicker()
    @subscriptions = []

    # Most of our initialization can be delayed until later.
    Promise.resolve().then(() =>
      require('atom-package-deps').install('atom-rtags-plus')

      {RtagsLinter} = require './linter.coffee'
      {RcExecutor} = require './rtags'
      {OpenFileTracker} = require('./open-file-tracker')
      @rcExecutor = new RcExecutor
      @linter = new RtagsLinter(@rcExecutor)
      @openFileTracker = new OpenFileTracker(@rcExecutor)
      @codeCompletionProvider.setRcExecutor(@rcExecutor)
      @hyperclickProvider.setRcExecutor(@rcExecutor)

      if (@indieRegistry)
        @linter.registerLinter(@indieRegistry)

      @codeCompletionProvider.doFuzzyCompletion = atom.config.get('atom-rtags-plus.fuzzyCodeCompletion')
      @subscriptions.push atom.config.observe('atom-rtags-plus.fuzzyCodeCompletion', (value) => @codeCompletionProvider.doFuzzyCompletion = value)

      # Register commands
      @subscriptions.push atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-symbol-at-point': => @findSymbolAtPoint()
      @subscriptions.push atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-references-at-point': => @findReferencesAtPoint()
      @subscriptions.push atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-all-references-at-point': => @findAllReferencesAtPoint()
      @subscriptions.push atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-virtuals-at-point': => @findVirtualsAtPoint()
      @subscriptions.push atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-symbols-by-keyword': => @findSymbolsByKeyword()
      @subscriptions.push atom.commands.add 'atom-workspace', 'atom-rtags-plus:find-references-by-keyword': => @findReferencesByKeyword()
      @subscriptions.push atom.commands.add 'atom-workspace', 'atom-rtags-plus:reindex-current-file': => @reindexCurrentFile()
      @subscriptions.push atom.commands.add 'atom-workspace', 'atom-rtags-plus:refactor-at-point': => @refactorAtPoint()
      #@subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:get-subclasses': => @get_subclasses()
      @subscriptions.push atom.commands.add 'atom-workspace', 'atom-rtags-plus:get-symbol-info': => @getSymbolInfo()
      #@subscriptions.add atom.commands.add 'atom-workspace', 'atom-rtags-plus:get-tokens': => @get_tokens()

      updateKeybindingMode(atom.config.get('atom-rtags-plus.keybindingStyle'));
      @subscriptions.push atom.config.observe('atom-rtags-plus.keybindingStyle', (value) => updateKeybindingMode(value)))

  deactivate: ->
    for subscription in @subscriptions
      subscription.dispose()
    @subscriptions = null
    @linter.destroy()
    @rcExecutor.destroy()
    @hyperclickProvider.destroy()
    @openFileTracker.destroy()

  # Toplevel function for linting. Provides a callback for every time rtags diagnostics outputs data
  # On new data we update the linter with our newly received results.
  consumeLinter: (indieRegistry) ->
    @indieRegistry = indieRegistry
    @linter?.registerLinter(@indieRegistry)

  # This is our autocompletion function.
  getCompletionProvider: ->
    @codeCompletionProvider

  getHyperclickProvider: ->
    @hyperclickProvider.getProvider()


  findSymbolAtPoint: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not n_util.matched_scope(active_editor)
    @rcExecutor.find_symbol_at_point(active_editor.getPath(), active_editor.getCursorBufferPosition()).then(([uri,r,c]) ->
      if !uri
        return
      atom.workspace.open uri, {'initialLine': r, 'initialColumn':c})
    .catch( (error) -> atom.notifications.addError(error))

  findReferencesAtPoint: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not n_util.matched_scope(active_editor)
    promise = @rcExecutor.find_references_at_point active_editor.getPath(), active_editor.getCursorBufferPosition()
    promise.then((out) =>
      @displayResultsInReferences(out))
    .catch((error) -> atom.notifications.addError(error))

  findAllReferencesAtPoint: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not n_util.matched_scope(active_editor)
    @rcExecutor.find_all_references_at_point(active_editor.getPath(), active_editor.getCursorBufferPosition())
    .then((out) =>
      @displayResultsInReferences(out))
    .catch((err) -> atom.notifications.addError(err))

  findVirtualsAtPoint: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not n_util.matched_scope(active_editor)
    @rcExecutor.find_virtuals_at_point(active_editor.getPath(), active_editor.getCursorBufferPosition()).then((out) =>
      @displayResultsInReferences(out))
    .catch((err) -> atom.notifications.addError(err))

  findSymbolsByKeyword: ->
    findSymbolCallback = (query) =>
      @rcExecutor.find_symbols_by_keyword(query).then((out) =>
        @displayResultsInReferences(out))
      .catch((err) -> atom.notifications.addError(err))

    @getSearchView().setTitle("Find symbols by keyword")
    @getSearchView().setSearchCallback(findSymbolCallback)
    @getSearchView().show()

  findReferencesByKeyword: ->
    findReferencesCallback = (query) =>
      @rcExecutor.find_references_by_keyword(query).then((out) =>
        @displayResultsInReferences(out))
      .catch((err) -> atom.notifications.addError(err))

    @getSearchView().setTitle("Find references by keyword")
    @getSearchView().setSearchCallback(findReferencesCallback)
    @getSearchView().show()

  reindexCurrentFile: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not n_util.matched_scope(active_editor)
    @rcExecutor.reindex_current_file(active_editor.getPath())
    .catch((err) -> atom.notifications.addError(err))

  refactorAtPoint: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not n_util.matched_scope(active_editor)
    refactorCallback = (replacement) =>
      @rcExecutor.get_refactor_locations(active_editor.getPath(), active_editor.getCursorBufferPosition())
      .then((paths) ->
        items = []
        {RtagsRefactorConfirmationNode, RtagsRefactorConfirmationPane} = require('./view/refactor-confirmation-view')
        confirmationPane = new RtagsRefactorConfirmationPane
        for path, refactorLines of paths
          items.push(new RtagsRefactorConfirmationNode({path: path, refactorLines: refactorLines, replacement: replacement}, 0, confirmationPane.referencesTree.redraw))
        confirmationPane.show()
        confirmationPane.referencesTree.setItems(items)
        )
      .catch((err) -> atom.notifications.addError(err))

    @getSearchView().setTitle("Rename item")
    @getSearchView().setSearchCallback(refactorCallback)
    @getSearchView().show()

  getReferencesView: ->
    RtagsReferencesTreePane = n_referencesTreeView.RtagsReferencesTreePane
    @referencesView ?= new RtagsReferencesTreePane()
    @referencesView

  getSearchView: ->
    @searchView ?= new n_rtagsSearchView.RtagsSearchView()
    return @searchView

  displayResultsInReferences: (res) ->
    if res.matchCount == 1
      for uri, v of res.res
        atom.workspace.open uri, {'initialLine': v[0], 'initialColumn':v[1]}
    references = []
    @getReferencesView().referencesTree.setItems([])
    for path, refArray of res.res
      for ref in refArray
        RtagsReferenceNode = n_referencesTreeView.RtagsReferenceNode
        references.push(new RtagsReferenceNode({ref: ref, path:path, rcExecutor: @rcExecutor}, 0, @referencesView.referencesTree.redraw))

    @referencesView.show()
    @referencesView.referencesTree.setItems(references)

  getSubclasses: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not n_util.matched_scope(active_editor)
    res = @rcExecutor.get_subclasses active_editor.getPath(), active_editor.getCursorBufferPosition()
    .catch((err) => atom.notifications.addError(err))

  getSymbolInfo: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not n_util.matched_scope(active_editor)
    res = @rcExecutor.get_symbol_info active_editor.getPath(), active_editor.getCursorBufferPosition()
    res.then( (out) ->
      atom.notifications.addInfo("Type of #{out.symbolName}:", {detail: out.type})
    )
    .catch( (err) -> atom.notifications.addError(err))

  getTokens: ->
    active_editor = atom.workspace.getActiveTextEditor()
    return if not active_editor
    return if not n_util.matched_scope(active_editor)
    @rcExecutor.get_tokens(active_editor.getPath()).then((out) =>
      console.log(out))
    .catch((err) -> atom.notifications.addError(err))
