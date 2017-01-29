{View, $} = require 'space-pen'

module.exports =
    class RtagsTooltip extends View
        @content: ->
            @div class: 'tooltip top in', =>
                @div class: 'tooltip-arrow', outlet: 'arrow'
                @div class: 'tooltip-inner', outlet: 'inner'


        initialize: ->
            $(document.body).append(@[0])
            window.setTimeout(@destroy, 3000)

        updateText: (text) ->
            @inner.text(text)

        updatePosition: (left, top) ->
            right = 0
            @.css({left, top})

        destroy: =>
            @.remove()
