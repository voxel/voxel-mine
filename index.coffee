# vim: set shiftwidth=2 tabstop=2 softtabstop=2 expandtab:

module.exports = (game, opts) ->
    return new Mine(game, opts)

Mine = (game, opts) ->
    this.game = game
    opts = opts ? {}
    opts.reachDistance ?= 8

    game.on 'fire', (target, state) =>
        if not state.fire
            # we only care about left-click
            return

        hit = game.raycastVoxels game.cameraPosition(), game.cameraVector(), opts.reachDistance 

        if not hit.voxel?
          console.log("no block mined")
          return

        this.game.setBlock hit.voxel, 0
        console.log "instamined ", hit.voxel
