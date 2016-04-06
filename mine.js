'use strict';

const EventEmitter = require('events').EventEmitter;

module.exports = (game, opts) => new Mine(game, opts);

module.exports.pluginInfo = {
  loadAfter: ['voxel-reach', 'voxel-registry', 'voxel-inventory-hotbar', 'voxel-decals', 'voxel-stitch']
}

class Mine extends EventEmitter {
  constructor(game, opts) {
    super();

    this.game = game;
    this.registry = game.plugins.get('voxel-registry');
    this.hotbar = game.plugins.get('voxel-inventory-hotbar');

    this.reach = game.plugins.get('voxel-reach');
    if (!this.reach) throw new Error('voxel-mine requires "voxel-reach" plugin');

    this.decals = game.plugins.get('voxel-decals');
    this.stitch = game.plugins.get('voxel-stitch');

    // continuous (non-discrete) firing is required to mine
    if (this.game.controls) {
      if (this.game.controls.needs_discrete_fire !== false) {
        throw new Error('voxel-mine requires discreteFire:false,fireRate:100 in voxel-control options (or voxel-engine controls discreteFire:false,fireRate:100)');
      }
      // TODO: can we just set needs_discrete_fire and fire_rate ourselves?
      this.secondsPerFire = this.game.controls.fire_rate / 1000;  // ms -> s
    } else {
      // server-side, game.controls unavailable, assume 100 ms TODO
      this.secondsPerFire = 100.0 / 1000.0;
    }

    if (!opts) opts = {};
    if (opts.instaMine === undefined) opts.instaMine = false;     // instantly mine? (if true, ignores timeToMine)
    if (opts.timeToMine === undefined) opts.timeToMine = undefined; // callback to get how long it should take to completely mine this block
    if (opts.progressTexturesPrefix === undefined) opts.progressTexturesPrefix = undefined; // prefix for damage overlay texture filenames; can be undefined to disable the overlay
    if (opts.progressTexturesCount === undefined) opts.progressTexturesCount = 10; // number of damage textures, cycles 0 to N-1, name = progressTexturesPrefix + #

    if (opts.applyTextureParams === undefined) {
      opts.applyTextureParams = (texture) => {
        texture.magFilter = this.game.THREE.NearestFilter;
        texture.minFilter = this.game.THREE.LinearMipMapLinearFilter;
        texture.wrapT = this.game.THREE.RepeatWrapping;
        texture.wrapS = this.game.THREE.RepeatWrapping;
      }
    }

    if (opts.defaultTextureURL === undefined) opts.defaultTextureURL = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAARElEQVQ4y62TMQoAMAgD8/9PX7cuhYLmnAQTQZMkCdkXT7Mhb5YwHkwwNOQfkOZJNDI1MncLsO5XFFA8oLhQyYGSxMs9lwAf4Z8BoD8AAAAASUVORK5CYII=';

    this.opts = opts;

    this.instaMine = opts.instaMine;
    this.progress = 0;

    if (this.game.isClient) {
      // texture overlays require three.js and textures, or voxel-decals with game.shell
      this.texturesEnabled = !this.opts.disableOverlay && this.opts.progressTexturesPrefix !== undefined;
      if (this.texturesEnabled && this.game.shell && !this.decals) {
          throw new Error('voxel-mine with game-shell requires voxel-decals to enable textures');
      }

      this.overlay = null;
      this.setupTextures();
    }

    this.enable();
  }

  // TODO
Mine::timeToMine = (target) ->
  return this.opts.timeToMine(target) if this.opts.timeToMine?  # custom callback

  # if no registry, can't lookup per-block hardness, use same for all
  return 9 if not this.registry

  # from registry, get the innate difficulty of mining this block
  blockID = game.getBlock(target.voxel)
  blockName = this.registry.getBlockName(blockID)
  hardness = this.registry.getProp(blockName, 'hardness') ? 1.0 # seconds

  effectiveTool = this.registry.getProp(blockName, 'effectiveTool') ? 'pickaxe'

  # if no held item concept, just use registry hardness
  return hardness if not this.hotbar

  # if hotbar is available - factor in effectiveness of currently held tool, shortens mining time
  heldItem = this.hotbar.held()
  toolClass = this.registry.getProp(heldItem?.item, 'toolClass')

  speed = 1.0

  if toolClass == effectiveTool
    # this tool is effective against this block, so it mines faster
    speed = this.registry.getProp(heldItem?.item, 'speed') ? 1.0
    # TODO: if wrong tool, deal double damage?


  finalTimeToMine = Math.max(hardness / speed, 0)
  # TODO: more complex mining 'classes', e.g. shovel against dirt, axe against wood

  return finalTimeToMine

Mine::enable = ->
  this.reach.on 'mining', this.onMining = (target) =>
    if not target
      console.log("no block mined")
      return

    this.progress += 1    # incremented each fire (this.secondsPerFire)
    progressSeconds = this.progress * this.secondsPerFire # how long they've been mining

    hardness = this.timeToMine(target)
    if this.instaMine || progressSeconds >= hardness
      this.progress = 0
      this.reach.emit 'stop mining', target
      this.emit 'break', target

    this.updateForStage(progressSeconds, hardness)

  this.reach.on 'start mining', this.onStartMining = (target) =>
    if not target
      return

    this.createOverlay(target)

  this.reach.on 'stop mining', this.onStopMining = (target) =>
    if not target
      return

    # Reset this.progress if mouse released
    this.destroyOverlay()
    this.progress = 0

Mine::disable = ->
  this.reach.removeListener 'mining', this.onMining
  this.reach.removeListener 'start mining', this.onStartMining
  this.reach.removeListener 'stop mining', this.onStopMining

Mine::setupTextures = ->
  if not this.texturesEnabled
    return

  this.progressTextures = []  # TODO: placeholders until loaded?

  this.registry.onTexturesReady () => this.refreshTextures()
  if this.game.materials?.artPacks?
    this.game.materials.artPacks.on 'refresh', () => this.refreshTextures()

  if this.decals
    # add to atlas
    for i in [0..this.opts.progressTexturesCount]
      name = this.opts.progressTexturesPrefix + i

      this.stitch.preloadTexture name

      this.progressTextures.push name

Mine::refreshTextures = ->
  if this.decals
    #
  else
    this.progressTextures = []
    for i in [0..this.opts.progressTexturesCount]
      path = this.registry.getTextureURL this.opts.progressTexturesPrefix + i
      if not path?
        # fallback to default texture if missing
        if this.defaultTextureURL.indexOf('data:') == 0
          # for some reason, data: URLs are not allowed with crossOrigin, see https://github.com/mrdoob/three.js/issues/687
          # warning: this might break other stuff
          delete this.game.THREE.ImageUtils.crossOrigin
        path = this.defaultTextureURL
      this.progressTextures.push(this.game.THREE.ImageUtils.loadTexture(path))

Mine::createOverlay = (target) ->
  if this.instaMine or not this.texturesEnabled
    return

  this.destroyOverlay()

  if this.decals
    this.decalPosition = target.voxel.slice(0)
    this.decalNormal = target.normal.slice(0)

    this.decals.add
      position: this.decalPosition
      normal: this.decalNormal
      texture: this.progressTextures[0]

    this.decals.update()
  else
    this.createOverlayThreejs(target)

Mine::createOverlayThreejs = (target) ->
  geometry = new this.game.THREE.Geometry()
  # TODO: actually compute this
  if target.normal[2] == 1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 1, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 0))
    offset = [0, 0, 1]
  else if target.normal[1] == 1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 0))
    offset = [0, 1, 0]
  else if target.normal[0] == 1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 1))
    offset = [1, 0, 0]
  else if target.normal[0] == -1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 0))
    offset = [0, 0, 0]
  else if target.normal[1] == -1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 1))
    offset = [0, 0, 0]
  else if target.normal[2] == -1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 1, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 0))
    offset = [0, 0, 0]
  else
    console.log "unknown face", target.normal
    return

  # rectangle geometry, see http://stackoverflow.com/questions/19085369/rendering-custom-geometry-in-three-js
  geometry.faces.push(new this.game.THREE.Face3(0, 1, 2)) # counter-clockwise winding order
  geometry.faces.push(new this.game.THREE.Face3(0, 2, 3))

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

  material = new this.game.THREE.MeshLambertMaterial()

  material.map = this.progressTextures[0]
  this.opts.applyTextureParams(material.map)

  material.side = this.game.THREE.FrontSide
  material.transparent = true
  material.polygonOffset = true
  material.polygonOffsetFactor = -1.0
  material.polygonOffsetUnits = -1.0
  mesh = new this.game.THREE.Mesh(geometry, material)
  this.overlay = new this.game.THREE.Object3D()

  this.overlay.add(mesh)
  this.overlay.position.set(target.voxel[0] + offset[0],
                   target.voxel[1] + offset[1],
                   target.voxel[2] + offset[2])

  this.game.scene.add(this.overlay)

  return this.overlay

# Set overlay texture based on mining progress stage
Mine::updateForStage = (progress, hardness) ->
  if not this.texturesEnabled
    return

  index = Math.floor((progress / hardness) * (this.progressTextures.length - 1))
  texture = this.progressTextures[index]

  this.setOverlayTexture(texture)

Mine::setOverlayTexture = (texture) ->
  if not this.texturesEnabled or (not this.overlay and not this.decalPosition)
    return

  if this.decals
    this.decals.change
      position: this.decalPosition
      normal: this.decalNormal
      texture: texture
    this.decals.update()
  else
    this.opts.applyTextureParams(texture)
    this.overlay.children[0].material.map = texture
    this.overlay.children[0].material.needsUpdate = true

Mine::destroyOverlay = () ->
  if not this.texturesEnabled or (not this.overlay and not this.decalPosition)
    return

  if this.decals
    this.decals.remove(this.decalPosition) if this.decalPosition?
    this.decals.update()
    this.decalPosition = undefined
  else
    this.game.scene.remove(this.overlay)
  this.overlay = null
