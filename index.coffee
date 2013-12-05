module.exports = (game, opts) ->
    return new Mine(game, opts)

Mine = (game, opts) ->
    this.game = game
    opts = opts ? {}

    console.log("mine")

