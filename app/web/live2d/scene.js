// 大肥鱼 as a Live2D model, in an iframe of the Flutter app
// (lib/widgets/live2d_figure_web.dart). Credits and licenses: README.md.
//
// Query:  ?framing=full|upper   the whole figure, or head and chest
//         ?follow=1             her eyes follow the pointer
//         ?props=0              no menu board and pen in her hands
//         ?upper=0.78           how much of her height `upper` shows (top down)
//         ?id=...               echoed in every message, so the app can tell
//                               its frames apart
//
// From the app:  {type:'mood',  mood:'smile'|'neutral'|'stern'|'angry'|'happy'}
//                {type:'state', state:'idle'|'listening'|'thinking'|'speaking'}
//                {type:'wave'}
//                {type:'react', kind:'surprised'|'happy'}
// To the app:    {source:'self-infinity-live2d', id, type:'ready'|'error', reason?}
//
// How the rig works (learned from Andersen216/dsh-whale-girl-live2d, MIT):
// the model's 44 "expressions" are VTube Studio parameter switches, all
// additive. The framework's expression manager is not used; looks are added in
// `beforeModelUpdate`, the last stop before the model is drawn (the framework
// restores the parameters at the end of every frame, so nothing accumulates).
// Head poses are set in `afterMotionUpdate`, before physics, so the hair
// follows them. The model's motion group `idle` is in fact a cat-paw wave with
// hearts, so it is the wave, played once; her idle sway is the framework's
// breathing and blinking plus physics.
;(function () {
  'use strict'

  const q = new URLSearchParams(location.search)
  const FRAMING = q.get('framing') === 'upper' ? 'upper' : 'full'
  const FOLLOW = q.get('follow') === '1'
  const PROPS = q.get('props') !== '0'
  const UPPER = clamp(Number(q.get('upper')) || 0.78, 0.2, 1)
  const ID = q.get('id') || ''

  const RUNTIME = [
    // Live2D Cubism Core: Live2D Proprietary Software License, from Live2D's CDN.
    'https://cubism.live2d.com/sdk-web/cubismcore/live2dcubismcore.min.js',
    'https://cdn.jsdelivr.net/npm/pixi.js@6.5.10/dist/browser/pixi.min.js',
    'https://cdn.jsdelivr.net/npm/pixi-live2d-display@0.4.0/dist/cubism4.min.js',
  ]
  const MODEL = 'model/c_0120.model3.json'
  const MANIFEST = 'model/manifest.json'
  const WAVE_MS = 4400

  // ------------------------------------------------------------ messaging

  let failed = false
  let ready = false

  function post(type, extra) {
    if (window.parent === window) return
    window.parent.postMessage(Object.assign({ source: 'self-infinity-live2d', id: ID, type }, extra || {}), '*')
  }

  function fail(reason) {
    if (failed || ready) return
    failed = true
    console.warn('[live2d]', reason)
    post('error', { reason: String(reason) })
  }

  // What the app asked for; kept even before the model is up.
  const want = { mood: 'neutral', state: 'idle' }
  const MOODS = ['smile', 'neutral', 'stern', 'angry', 'happy']
  const STATES = ['idle', 'listening', 'thinking', 'speaking']

  window.addEventListener('message', (event) => {
    if (event.source !== window.parent) return
    const m = event.data
    if (!m || typeof m !== 'object') return
    switch (m.type) {
      case 'mood':
        if (MOODS.includes(m.mood)) want.mood = m.mood
        break
      case 'state':
        if (STATES.includes(m.state)) want.state = m.state
        break
      case 'wave':
        wave()
        break
      case 'react':
        react(m.kind)
        break
    }
  })

  // ------------------------------------------------------------ boot

  function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v))
  }

  function hasWebGL() {
    try {
      const c = document.createElement('canvas')
      return !!(c.getContext('webgl2') || c.getContext('webgl'))
    } catch (e) {
      return false
    }
  }

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const s = document.createElement('script')
      s.src = src
      s.crossOrigin = 'anonymous'
      s.onload = resolve
      s.onerror = () => reject(new Error('could not load ' + src))
      document.head.appendChild(s)
    })
  }

  async function loadJson(url) {
    const r = await fetch(url)
    if (!r.ok) throw new Error(url + ': ' + r.status)
    return r.json()
  }

  const expressionUrl = (name) => 'model/expressions/' + encodeURIComponent(name) + '.exp3.json'

  let app = null
  let model = null
  let core = null
  let manifest = null
  let contentBox = null // the figure's drawn extent, in model units

  async function boot() {
    if (!hasWebGL()) throw new Error('no WebGL')
    for (const src of RUNTIME) await loadScript(src)
    if (!window.PIXI || !PIXI.live2d || !window.Live2DCubismCore) throw new Error('runtime missing')

    const [mf, exprs] = await Promise.all([
      loadJson(MANIFEST).catch(() => null),
      Promise.all(EXPRESSIONS.map((n) => loadJson(expressionUrl(n)).then((j) => [n, j]))),
    ])
    manifest = mf
    for (const [name, json] of exprs) {
      EXPR[name] = (json.Parameters || []).map((p) => ({ id: p.Id, value: Number(p.Value) || 0 }))
    }
    buildLooks()

    app = new PIXI.Application({
      resizeTo: window,
      backgroundAlpha: 0,
      antialias: true,
      autoDensity: true,
      resolution: Math.min(window.devicePixelRatio || 1, 2),
      powerPreference: 'low-power',
    })
    app.ticker.maxFPS = 30
    PIXI.Ticker.shared.maxFPS = 30
    document.body.appendChild(app.view)

    const { Live2DModel } = PIXI.live2d
    Live2DModel.registerTicker(PIXI.Ticker)
    model = await Live2DModel.from(MODEL, { autoInteract: false, autoUpdate: true })
    app.stage.addChild(model)

    const internal = model.internalModel
    core = internal.coreModel
    internal.on('afterMotionUpdate', applyPose)
    internal.on('beforeModelUpdate', applyLooks)

    // Let physics settle, then find where she is drawn and frame her.
    await frames(20)
    contentBox = measure() || { x: 0, y: 0, w: internal.width, h: internal.height }
    // For tuning the framing from the console.
    window.live2dDebug = { model, contentBox, layout, internal }
    layout()
    window.addEventListener('resize', layout)
    if (FOLLOW) followPointer()

    document.addEventListener('visibilitychange', () => {
      const t = [app.ticker, PIXI.Ticker.shared]
      for (const k of t) document.hidden ? k.stop() : k.start()
    })

    await frames(2)
    app.view.classList.add('on')
    ready = true
    post('ready')
  }

  function frames(n) {
    return new Promise((resolve) => {
      const step = () => (--n <= 0 ? resolve() : requestAnimationFrame(step))
      requestAnimationFrame(step)
    })
  }

  // ------------------------------------------------------------ framing

  // Draws the whole model into the canvas once and reads the alpha back: the
  // model is a desk scene, and its canvas has a lot of air around her.
  function measure() {
    try {
      const im = model.internalModel
      const W = app.screen.width
      const H = app.screen.height
      const s = Math.min(W / im.width, H / im.height)
      model.scale.set(s)
      model.position.set(0, 0)
      app.renderer.render(app.stage)
      const gl = app.renderer.gl
      const pw = gl.drawingBufferWidth
      const ph = gl.drawingBufferHeight
      const px = new Uint8Array(pw * ph * 4)
      gl.readPixels(0, 0, pw, ph, gl.RGBA, gl.UNSIGNED_BYTE, px)
      const res = app.renderer.resolution
      let x0 = pw, x1 = -1, y0 = ph, y1 = -1
      for (let y = 0; y < ph; y += 2) {
        for (let x = 0; x < pw; x += 2) {
          if (px[(y * pw + x) * 4 + 3] > 12) {
            if (x < x0) x0 = x
            if (x > x1) x1 = x
            if (y < y0) y0 = y
            if (y > y1) y1 = y
          }
        }
      }
      if (x1 < 0) return null
      // readPixels rows run bottom up.
      const top = ph - 1 - y1
      const bottom = ph - 1 - y0
      // The head: the middle of what is drawn in the top fifth.
      const band = top + (bottom - top) * 0.2
      let sum = 0, count = 0
      for (let y = Math.max(0, ph - 1 - Math.round(band)); y <= y1; y += 2) {
        for (let x = x0; x <= x1; x += 2) {
          if (px[(y * pw + x) * 4 + 3] > 12) { sum += x; count++ }
        }
      }
      const toModel = (v) => v / res / s
      return {
        x: toModel(x0),
        y: toModel(top),
        w: toModel(x1 - x0),
        h: toModel(bottom - top),
        headX: toModel(count ? sum / count : (x0 + x1) / 2),
      }
    } catch (e) {
      console.warn('[live2d] measure failed', e)
      return null
    }
  }

  function layout() {
    if (!model || !contentBox) return
    const W = app.screen.width
    const H = app.screen.height
    const b = contentBox
    let box
    if (FRAMING === 'upper') {
      const h = b.h * UPPER
      const w = Math.min(b.w, h * 0.95)
      const cx = b.headX != null ? b.headX : b.x + b.w / 2
      box = { x: cx - w / 2, y: b.y, w, h }
    } else {
      box = b
    }
    const pad = 0.04
    const s = Math.min(W / (box.w * (1 + pad * 2)), H / (box.h * (1 + pad * 2)))
    model.scale.set(s)
    // Centred across; standing on the bottom edge (upper: cut at the chest).
    model.position.set(W / 2 - (box.x + box.w / 2) * s, H - (box.y + box.h) * s - (FRAMING === 'full' ? H * pad * 0.5 : 0))
  }

  function followPointer() {
    window.addEventListener('pointermove', (e) => model && model.focus(e.clientX, e.clientY))
    const centre = () => model && model.internalModel.focusController.focus(0, 0)
    document.addEventListener('pointerleave', centre)
    window.addEventListener('blur', centre)
  }

  // ------------------------------------------------------------ looks

  // The model's own expressions this page uses (model/expressions/*.exp3.json).
  const EXPRESSIONS = ['喵喵手~喵~动画', '开心兴奋', '生气', '阴暗', '感叹号', 'love', '脸红', '点菜按下', '画笔']
  const EXPR = {}
  const LOOK = {}

  function buildLooks() {
    const e = (n) => EXPR[n] || []
    const p = (id, value) => ({ id, value })
    // Moods.
    LOOK.smile = [p('ParamMouthForm', 0.6)]
    LOOK.neutral = []
    LOOK.stern = [
      p('ParamBrowLY', -0.3), p('ParamBrowRY', -0.3),
      p('ParamBrowLAngle', -0.5), p('ParamBrowRAngle', -0.5),
      p('ParamMouthForm', -0.5),
    ]
    LOOK.angry = e('生气').concat(e('阴暗')) // knitted brows, pout and the dark face
    LOOK.happy = e('开心兴奋') // ^^ eyes and a wide smile
    // Reactions.
    LOOK.surprised = e('感叹号').concat([p('ParamBrowLY', 0.7), p('ParamBrowRY', 0.7), p('ParamMouthForm', -0.3)])
    // The wave: her cat paws out (the motion then moves them) and hearts.
    LOOK.wave = e('喵喵手~喵~动画').concat(e('love'))
    LOOK.delight = e('开心兴奋').concat(e('love'), e('脸红'))
    // Her hands: the menu board and pen she holds by default in the author's design.
    LOOK.props = PROPS ? e('点菜按下').concat(e('画笔')) : []
  }

  // Each look fades in and out by its own weight.
  const weight = new Map()
  let reaction = null // {look, until}

  function react(kind) {
    const look = kind === 'surprised' ? 'surprised' : kind === 'happy' ? 'delight' : null
    if (!look) return
    reaction = { look, until: performance.now() + (look === 'surprised' ? 1600 : 2400) }
  }

  let last = 0
  let talk = 0
  let talkPhase = 0

  function applyLooks() {
    const now = performance.now()
    const dt = Math.min(0.064, (now - (last || now)) / 1000)
    last = now
    if (reaction && now > reaction.until) reaction = null

    // Which looks should be on, highest priority first.
    const on = []
    if (reaction) on.push(reaction.look)
    if (waveTimer) on.push('wave')
    on.push(want.mood)
    on.push('props')

    for (const name of on) if (!weight.has(name)) weight.set(name, 0)
    for (const [name, w] of weight) {
      const target = on.includes(name) ? 1 : 0
      const next = w + (target - w) * clamp(dt * (target > w ? 7 : 10), 0, 1)
      if (target === 0 && next < 0.02) weight.delete(name)
      else weight.set(name, next)
    }

    // One writer per parameter: the higher look wins; fading ones fill in.
    const order = on.concat([...weight.keys()].filter((n) => !on.includes(n)))
    const claimed = new Set()
    for (const name of order) {
      const w = weight.get(name) || 0
      if (w <= 0) continue
      for (const { id, value } of LOOK[name] || []) {
        if (claimed.has(id)) continue
        claimed.add(id)
        add(id, value * w)
      }
    }

    // Speaking: the mouth opens and closes in an uneven rhythm.
    talk += ((want.state === 'speaking' ? 1 : 0) - talk) * clamp(dt * 8, 0, 1)
    if (talk > 0.01) {
      talkPhase += dt
      const open = 0.5 + 0.5 * Math.sin(talkPhase * 10.7)
      const env = 0.65 + 0.35 * Math.sin(talkPhase * 2.3)
      add('ParamMouthOpenY', talk * 0.55 * open * env)
    }

    // Thinking: eyes up and aside.
    const th = pose.cur.think
    if (th > 0.01) {
      add('ParamEyeBallX', -0.45 * th)
      add('ParamEyeBallY', 0.5 * th)
    }
  }

  function add(id, v) {
    if (Math.abs(v) < 0.001) return
    try {
      core.addParameterValueById(id, v)
    } catch (e) {}
  }

  // ------------------------------------------------------------ poses

  // Head and body offsets per state, in the model's angle units (degrees).
  const POSES = {
    idle: { ax: 0, ay: 0, az: 0, bz: 0, think: 0 },
    listening: { ax: 2, ay: 4, az: 7, bz: 2, think: 0 },
    thinking: { ax: -6, ay: 7, az: -10, bz: -2, think: 1 },
    speaking: { ax: 0, ay: 1, az: 0, bz: 0, think: 0 },
  }
  const pose = { cur: Object.assign({}, POSES.idle), last: 0, t: 0 }
  const POSE_PARAMS = { ax: 'ParamAngleX', ay: 'ParamAngleY', az: 'ParamAngleZ', bz: 'ParamBodyAngleZ' }
  const defaults = {}

  function paramDefault(id) {
    if (id in defaults) return defaults[id]
    let d = null
    try {
      const i = core.getParameterIndex(id)
      if (typeof i === 'number' && i >= 0) {
        const v = core.getParameterDefaultValue(i)
        if (typeof v === 'number' && Number.isFinite(v)) d = v
      }
    } catch (e) {}
    return (defaults[id] = d)
  }

  // Set, not added: this runs before the framework saves the parameters, so an
  // addition would pile up frame after frame.
  function applyPose() {
    const now = performance.now()
    const dt = Math.min(0.064, (now - (pose.last || now)) / 1000)
    pose.last = now
    pose.t += dt
    const target = POSES[want.state] || POSES.idle
    const k = clamp(dt * 3.5, 0, 1)
    for (const key of Object.keys(pose.cur)) pose.cur[key] += (target[key] - pose.cur[key]) * k
    // A small nod while speaking.
    const nod = want.state === 'speaking' ? 2 * Math.sin(pose.t * 3.1) : 0
    for (const [key, id] of Object.entries(POSE_PARAMS)) {
      const d = paramDefault(id)
      if (d === null) continue
      const v = pose.cur[key] + (key === 'ay' ? nod : 0)
      try {
        core.setParameterValueById(id, d + v)
      } catch (e) {}
    }
  }

  // ------------------------------------------------------------ wave

  let waveTimer = null

  // The model's `idle` motion moves her cat paws and floats hearts up; the
  // paws themselves are the `喵喵手` switch, so the wave look turns it on for
  // as long. The motion loops in the file, so it is stopped by hand and its
  // pose cleared.
  function wave() {
    if (!model) return
    try {
      stopWave()
      model.motion('idle', 0, 3) // 3: MotionPriority.FORCE
      waveTimer = setTimeout(stopWave, WAVE_MS)
    } catch (e) {
      console.warn('[live2d] wave failed', e)
    }
  }

  function stopWave() {
    if (waveTimer) clearTimeout(waveTimer)
    waveTimer = null
    try {
      model.internalModel.motionManager.stopAllMotions()
    } catch (e) {}
    // The framework saved the motion's last frame as the pose it restores every
    // frame; put those parameters back to their defaults and save again.
    const ids = (manifest && manifest.motions && manifest.motions.idle && manifest.motions.idle.params) || []
    for (const id of ids) {
      const d = paramDefault(id)
      if (d === null) continue
      try {
        core.setParameterValueById(id, d)
      } catch (e) {}
    }
    try {
      core.saveParameters()
    } catch (e) {}
  }

  // ------------------------------------------------------------ go

  const timeout = setTimeout(() => fail('timeout'), 25000)
  boot()
    .then(() => clearTimeout(timeout))
    .catch((e) => {
      clearTimeout(timeout)
      fail(e && e.message ? e.message : e)
    })
})()
