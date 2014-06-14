EventEmitter = (require 'events').EventEmitter

module.exports = (game, opts) ->
  return new Mine(game, opts)

module.exports.pluginInfo =
  loadAfter: ['voxel-reach', 'voxel-registry', 'voxel-inventory-hotbar', 'voxel-decals', 'voxel-stitch']

class Mine extends EventEmitter
  constructor: (game, opts) ->
    @game = game
    @registry = game.plugins?.get('voxel-registry')
    @hotbar = game.plugins?.get('voxel-inventory-hotbar')
    @reach = game.plugins?.get('voxel-reach') ? throw new Error('voxel-mine requires "voxel-reach" plugin')
    @decals = game.plugins?.get('voxel-decals') # optional
    @stitch = game.plugins?.get('voxel-stitch') # optional

    # continuous (non-discrete) firing is required to mine
    if @game.controls?
      throw new Error('voxel-mine requires discreteFire:false,fireRate:100 in voxel-control options (or voxel-engine controls:{discreteFire:false,fireRate:100}})') if @game.controls.needs_discrete_fire != false
      # TODO: can we just set needs_discrete_fire and fire_rate ourselves?
      @secondsPerFire = @game.controls.fire_rate / 1000  # ms -> s
    else
      # server-side, game.controls unavailable, assume 100 ms TODO
      @secondsPerFire = 100.0 / 1000.0

    opts = opts ? {}
    opts.instaMine ?= false     # instantly mine? (if true, ignores timeToMine)
    opts.timeToMine ?= undefined         # callback to get how long it should take to completely mine this block
    opts.progressTexturesPrefix ?= undefined # prefix for damage overlay texture filenames; can be undefined to disable the overlay
    opts.progressTexturesCount ?= 10         # number of damage textures, cycles 0 to N-1, name = progressTexturesPrefix + #

    opts.applyTextureParams ?= (texture) =>
      texture.magFilter = @game.THREE.NearestFilter
      texture.minFilter = @game.THREE.LinearMipMapLinearFilter
      texture.wrapT = @game.THREE.RepeatWrapping
      texture.wrapS = @game.THREE.RepeatWrapping

    @defaultTextureURL = opts.defaultTextureURL ? 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAARElEQVQ4y62TMQoAMAgD8/9PX7cuhYLmnAQTQZMkCdkXT7Mhb5YwHkwwNOQfkOZJNDI1MncLsO5XFFA8oLhQyYGSxMs9lwAf4Z8BoD8AAAAASUVORK5CYII='

    @opts = opts

    @instaMine = opts.instaMine
    @progress = 0

    if @game.isClient
      # texture overlays require three.js and textures, or voxel-decals with game.shell
      @texturesEnabled = !!(!@opts.disableOverlay && @opts.progressTexturesPrefix? && (!@game.shell? || @decals))

      @overlay = null
      @setupTextures()

    @enable()

Mine::timeToMine = (target) ->
  return @opts.timeToMine(target) if @opts.timeToMine?  # custom callback

  # if no registry, can't lookup per-block hardness, use same for all
  return 9 if not @registry

  # from registry, get the innate difficulty of mining this block
  blockID = game.getBlock(target.voxel)
  blockName = @registry.getBlockName(blockID)
  hardness = @registry.getProp(blockName, 'hardness') ? 1.0 # seconds

  effectiveTool = @registry.getProp(blockName, 'effectiveTool') ? 'pickaxe'

  # if no held item concept, just use registry hardness
  return hardness if not @hotbar

  # if hotbar is available - factor in effectiveness of currently held tool, shortens mining time
  heldItem = @hotbar.held()
  toolClass = @registry.getProp(heldItem?.item, 'toolClass')

  speed = 1.0

  if toolClass == effectiveTool
    # this tool is effective against this block, so it mines faster
    speed = @registry.getProp(heldItem?.item, 'speed') ? 1.0
    # TODO: if wrong tool, deal double damage?


  finalTimeToMine = Math.max(hardness / speed, 0)
  # TODO: more complex mining 'classes', e.g. shovel against dirt, axe against wood

  return finalTimeToMine

Mine::enable = ->
  @reach.on 'mining', @onMining = (target) =>
    if not target
      console.log("no block mined")
      return

    @progress += 1    # incremented each fire (@secondsPerFire)
    progressSeconds = @progress * @secondsPerFire # how long they've been mining

    hardness = @timeToMine(target)
    if @instaMine || progressSeconds >= hardness
      @progress = 0
      @reach.emit 'stop mining', target
      @emit 'break', target

    @updateForStage(progressSeconds, hardness)

  @reach.on 'start mining', @onStartMining = (target) =>
    if not target
      return

    @createOverlay(target)

  @reach.on 'stop mining', @onStopMining = (target) =>
    if not target
      return

    # Reset @progress if mouse released
    @destroyOverlay()
    @progress = 0

Mine::disable = ->
  @reach.removeListener 'mining', @onMining
  @reach.removeListener 'start mining', @onStartMining
  @reach.removeListener 'stop mining', @onStopMining

Mine::setupTextures = ->
  if not @texturesEnabled
    return

  @progressTextures = []  # TODO: placeholders until loaded?

  @registry.onTexturesReady () => @refreshTextures()
  if @game.materials?.artPacks?
    @game.materials.artPacks.on 'refresh', () => @refreshTextures()

  if @decals
    # add to atlas
    for i in [0..@opts.progressTexturesCount]
      name = @opts.progressTexturesPrefix + i

      @stitch.preloadTexture name

      @progressTextures.push name

Mine::refreshTextures = ->
  if @decals
    #
  else
    @progressTextures = []
    for i in [0..@opts.progressTexturesCount]
      path = @registry.getTextureURL @opts.progressTexturesPrefix + i
      if not path?
        # fallback to default texture if missing
        if @defaultTextureURL.indexOf('data:') == 0
          # for some reason, data: URLs are not allowed with crossOrigin, see https://github.com/mrdoob/three.js/issues/687
          # warning: this might break other stuff
          delete this.game.THREE.ImageUtils.crossOrigin
        path = @defaultTextureURL
      @progressTextures.push(@game.THREE.ImageUtils.loadTexture(path))

Mine::createOverlay = (target) ->
  if @instaMine or not @texturesEnabled
    return

  @destroyOverlay()

  if @decals
    @decalPosition = target.voxel.slice(0)
    @decalNormal = target.normal.slice(0)

    @decals.add
      position: @decalPosition
      normal: @decalNormal
      texture: @progressTextures[0]

    @decals.update()
  else
    @createOverlayThreejs(target)

Mine::createOverlayThreejs = (target) ->
  geometry = new @game.THREE.Geometry()
  # TODO: actually compute this
  if target.normal[2] == 1
    geometry.vertices.push(new @game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new @game.THREE.Vector3(1, 0, 0))
    geometry.vertices.push(new @game.THREE.Vector3(1, 1, 0))
    geometry.vertices.push(new @game.THREE.Vector3(0, 1, 0))
    offset = [0, 0, 1]
  else if target.normal[1] == 1
    geometry.vertices.push(new @game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new @game.THREE.Vector3(0, 0, 1))
    geometry.vertices.push(new @game.THREE.Vector3(1, 0, 1))
    geometry.vertices.push(new @game.THREE.Vector3(1, 0, 0))
    offset = [0, 1, 0]
  else if target.normal[0] == 1
    geometry.vertices.push(new @game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new @game.THREE.Vector3(0, 1, 0))
    geometry.vertices.push(new @game.THREE.Vector3(0, 1, 1))
    geometry.vertices.push(new @game.THREE.Vector3(0, 0, 1))
    offset = [1, 0, 0]
  else if target.normal[0] == -1
    geometry.vertices.push(new @game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new @game.THREE.Vector3(0, 0, 1))
    geometry.vertices.push(new @game.THREE.Vector3(0, 1, 1))
    geometry.vertices.push(new @game.THREE.Vector3(0, 1, 0))
    offset = [0, 0, 0]
  else if target.normal[1] == -1
    geometry.vertices.push(new @game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new @game.THREE.Vector3(1, 0, 0))
    geometry.vertices.push(new @game.THREE.Vector3(1, 0, 1))
    geometry.vertices.push(new @game.THREE.Vector3(0, 0, 1))
    offset = [0, 0, 0]
  else if target.normal[2] == -1
    geometry.vertices.push(new @game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new @game.THREE.Vector3(0, 1, 0))
    geometry.vertices.push(new @game.THREE.Vector3(1, 1, 0))
    geometry.vertices.push(new @game.THREE.Vector3(1, 0, 0))
    offset = [0, 0, 0]
  else
    console.log "unknown face", target.normal
    return

  # rectangle geometry, see http://stackoverflow.com/questions/19085369/rendering-custom-geometry-in-three-js
  geometry.faces.push(new @game.THREE.Face3(0, 1, 2)) # counter-clockwise winding order
  geometry.faces.push(new @game.THREE.Face3(0, 2, 3))

  geometry.computeCentroids()
  geometry.computeFaceNormals()
  geometry.computeVertexNormals()
  geometry.faceVertexUvs = [
      [
        [
          {x:0, y:0},
          {x:1, y:0},
          {x:1, y:1},
          {x:0, y:1}
        ],
        [
          {x:0, y:0},
          {x:1, y:1},
          {x:0, y:1},
          {x:0, y:1},
        ],
      ]
    ]

  material = new @game.THREE.MeshLambertMaterial()

  material.map = @progressTextures[0]
  @opts.applyTextureParams(material.map)

  material.side = @game.THREE.FrontSide
  material.transparent = true
  material.polygonOffset = true
  material.polygonOffsetFactor = -1.0
  material.polygonOffsetUnits = -1.0
  mesh = new @game.THREE.Mesh(geometry, material)
  @overlay = new @game.THREE.Object3D()

  @overlay.add(mesh)
  @overlay.position.set(target.voxel[0] + offset[0],
                   target.voxel[1] + offset[1],
                   target.voxel[2] + offset[2])

  @game.scene.add(@overlay)

  return @overlay

# Set overlay texture based on mining progress stage
Mine::updateForStage = (progress, hardness) ->
  if not @texturesEnabled
    return

  index = Math.floor((progress / hardness) * (@progressTextures.length - 1))
  texture = @progressTextures[index]

  @setOverlayTexture(texture)

Mine::setOverlayTexture = (texture) ->
  if not @texturesEnabled or (not @overlay and not @decalPosition)
    return

  if @decals
    @decals.change
      position: @decalPosition
      normal: @decalNormal
      texture: texture
    @decals.update()
  else
    @opts.applyTextureParams(texture)
    @overlay.children[0].material.map = texture
    @overlay.children[0].material.needsUpdate = true

Mine::destroyOverlay = () ->
  if not @texturesEnabled or (not @overlay and not @decalPosition)
    return

  if @decals
    @decals.remove(@decalPosition) if @decalPosition?
    @decals.update()
    @decalPosition = undefined
  else
    @game.scene.remove(@overlay)
  @overlay = null
