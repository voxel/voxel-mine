# vim: set shiftwidth=2 tabstop=2 softtabstop=2 expandtab:

EventEmitter = (require 'events').EventEmitter

module.exports = (game, opts) ->
  return new Mine(game, opts)

module.exports.pluginInfo =
  loadAfter: ['reach']

class Mine extends EventEmitter
  constructor: (game, opts) ->
    @game = game
    opts = opts ? {}
    opts.timeToMine ?= (voxel) => 9         # callback to get how long it should take to completely mine this block
    opts.instaMine ?= false     # instantly mine?
    opts.progressTexturesPrefix ?= undefined # prefix for damage overlay texture filenames; can be undefined to disable the overlay
    opts.progressTexturesExt ?= ".png"       # suffix for path of damage texture overlay
    opts.progressTexturesCount ?= 10         # number of damage textures, cycles 0 to N-1, path = game.materials.texturePath + progressTextures{Prefix+#+Ext}

    opts.applyTextureParams ?= (texture) =>
      texture.magFilter = @game.THREE.NearestFilter
      texture.minFilter = @game.THREE.LinearMipMapLinearFilter
      texture.wrapT = @game.THREE.RepeatWrapping
      texture.wrapS = @game.THREE.RepeatWrapping

    @reach = game.plugins?.all.reach ? throw 'voxel-mine requires "voxel-reach" plugin'
    # TODO: voxel-registry plugin to get texture paths?

    @opts = opts

    @instaMine = opts.instaMine
    @progress = 0

    @texturesEnabled = @opts.progressTexturesPrefix?
    @overlay = null
    @setupTextures()
    @enable()

Mine::enable = ->
  @reach.on 'mining', @onMining = (target) =>
    if not target
      console.log("no block mined")
      return

    @progress += 1

    hardness = @opts.timeToMine(target)
    if @instaMine || @progress > hardness
      @progress = 0
      @reach.emit 'stop mining', target
      @emit 'break', target

    @updateForStage(@progress, hardness)

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

  @progressTextures = []

  for i in [0..@opts.progressTexturesCount]
    path = (@game.materials.texturePath ? '') + @opts.progressTexturesPrefix + i + @opts.progressTexturesExt
    @progressTextures.push(@game.THREE.ImageUtils.loadTexture(path))

Mine::createOverlay = (target) ->
  if @instaMine or not @texturesEnabled
    return

  @destroyOverlay()

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
  if not @overlay or not @texturesEnabled
    return

  @opts.applyTextureParams(texture)
  @overlay.children[0].material.map = texture
  @overlay.children[0].material.needsUpdate = true

Mine::destroyOverlay = () ->
  if not @overlay or not @texturesEnabled
    return

  @game.scene.remove(@overlay)
  @overlay = null
