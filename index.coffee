# vim: set shiftwidth=2 tabstop=2 softtabstop=2 expandtab:

module.exports = (game, opts) ->
  return new Mine(game, opts)

Mine = (game, opts) ->
  this.game = game
  opts = opts ? {}
  opts.reachDistance ?= 8

  game.on 'break', (hit_voxel) =>
    if not hit_voxel?
      console.log("no block mined")
      return

    this.game.setBlock hit_voxel, 0
