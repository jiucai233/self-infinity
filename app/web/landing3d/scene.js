// The front page's robot: a glossy black mannequin holding a glowing orb. The
// page (lib/features/auth/landing_page.dart) sends its scroll progress, 0 at
// the hero to 5 at the end, and this scene answers with where the orb is, so
// the page can draw the life tree out of it.
//
//   page -> scene  {source: 'self-infinity-page', p}
//   scene -> page  {source: 'self-infinity-robot', type: 'ready' | 'unsupported'}
//                  {source: 'self-infinity-robot', type: 'orb', x, y, r}   (CSS px)
//
// Opened alone, `?p=2.5` shows one moment (for checking the look).
//
// The model is three.js's Xbot (examples/models/gltf/Xbot.glb, a Mixamo
// character). Its right arm, fingers and head are posed here; the rest plays
// its idle clip.

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const PAPER = 0xfbfbf8; // AppColors.surface
const query = new URLSearchParams(location.search);
let target = Number(query.get('p') ?? 0);
let progress = target;

const post = (message) => window.parent?.postMessage({ source: 'self-infinity-robot', ...message }, '*');

addEventListener('message', (event) => {
  const data = event.data;
  if (data && data.source === 'self-infinity-page' && Number.isFinite(data.p)) target = data.p;
});

// ------------------------------------------------------------------ renderer

let renderer;
try {
  renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: query.has('p') });
} catch {
  post({ type: 'unsupported' });
  throw new Error('no WebGL');
}
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setClearColor(PAPER, 0);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(30, 1, 0.05, 50);

// A dark studio with coloured strip lights: what the black lacquer reflects.
function studio() {
  const room = new THREE.Scene();
  room.add(new THREE.Mesh(new THREE.BoxGeometry(12, 12, 12), new THREE.MeshBasicMaterial({ color: 0x15151a, side: THREE.BackSide })));
  const panel = (color, strength, w, h, x, y, z) => {
    const mesh = new THREE.Mesh(
      new THREE.PlaneGeometry(w, h),
      new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(strength), side: THREE.DoubleSide }),
    );
    mesh.position.set(x, y, z);
    mesh.lookAt(0, 1, 0);
    room.add(mesh);
  };
  panel(0xffffff, 7, 5, 1.4, 0.5, 5.5, 2);   // the softbox overhead
  panel(0xfff6ea, 0.7, 5, 2, 0, 1.5, 5.8);   // the paper in front
  panel(0x8b5cff, 6, 1.1, 7, -5.5, 1.5, 0.5); // violet, left
  panel(0x3fd8ff, 5, 1.1, 7, 5.5, 1.5, -0.5); // teal, right
  panel(0xff5fc8, 3, 4, 1, 0, -2.5, -4);     // magenta, low behind
  return room;
}
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(studio(), 0.03).texture;

const key = new THREE.DirectionalLight(0xffffff, 1.6);
key.position.set(0.5, 5, 1.2);
key.castShadow = true;
key.shadow.mapSize.set(2048, 2048);
key.shadow.camera.left = -1.5;
key.shadow.camera.right = 1.5;
key.shadow.camera.top = 1.5;
key.shadow.camera.bottom = -1.5;
key.shadow.radius = 6;
key.shadow.bias = -0.0005;
scene.add(key);

const floor = new THREE.Mesh(new THREE.PlaneGeometry(20, 20), new THREE.ShadowMaterial({ opacity: 0.12 }));
floor.rotation.x = -Math.PI / 2;
floor.receiveShadow = true;
scene.add(floor);

// ------------------------------------------------------------------ the orb

const ORB_VERTEX = /* glsl */ `
  varying vec3 vNormal;
  varying vec3 vView;
  varying vec3 vLocal;
  void main() {
    vLocal = position;
    vec4 mv = modelViewMatrix * vec4(position, 1.0);
    vView = -mv.xyz;
    vNormal = normalize(normalMatrix * normal);
    gl_Position = projectionMatrix * mv;
  }
`;

// Ashima's 3D simplex noise (MIT), then ridged noise for glowing veins.
const ORB_FRAGMENT = /* glsl */ `
  uniform float uTime;
  uniform vec3 uCamera; // the camera, in the orb's own space
  uniform vec3 uLight;  // toward the key light, in view space
  varying vec3 vNormal;
  varying vec3 vView;
  varying vec3 vLocal;

  vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
  vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }
  float snoise(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
    vec3 i = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);
    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;
    i = mod289(i);
    vec4 p = permute(permute(permute(i.z + vec4(0.0, i1.z, i2.z, 1.0)) + i.y + vec4(0.0, i1.y, i2.y, 1.0)) + i.x + vec4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    vec3 ns = n_ * D.wyz - D.xzx;
    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);
    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);
    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);
    vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
  }

  float veins(vec3 q, float sharp) {
    return pow(1.0 - abs(snoise(q)), sharp);
  }

  void main() {
    vec3 n = normalize(vNormal);
    vec3 v = normalize(vView);
    float facing = clamp(dot(n, v), 0.0, 1.0);
    float rim = pow(1.0 - facing, 2.4);

    // Glass: veins on the surface, and fainter ones deeper inside, seen
    // through it (stepping from the surface away from the camera).
    vec3 inward = normalize(vLocal - uCamera);
    vec3 drift = vec3(0.0, uTime * 0.06, uTime * 0.025);
    float front = veins(vLocal * 2.2 + drift, 10.0) + 0.5 * veins(vLocal * 4.6 + drift * 1.7 + 3.0, 14.0);
    vec3 deep = vLocal + inward * 0.75 * facing;
    float back = veins(deep * 2.6 - drift + 11.0, 7.0);

    vec3 ember = vec3(0.62, 0.2, 0.01);
    vec3 amber = vec3(0.98, 0.45, 0.04);
    vec3 gold = vec3(1.0, 0.7, 0.2);
    vec3 hot = vec3(1.0, 0.95, 0.74);
    vec3 color = mix(ember, amber, smoothstep(0.0, 0.6, facing));
    color = mix(color, gold, 0.45 * back + 0.25 * pow(facing, 3.0));
    color = mix(color, hot, 0.65 * clamp(front, 0.0, 1.0));
    color += vec3(1.0, 0.78, 0.4) * rim * 0.7;
    float shine = pow(max(dot(reflect(-uLight, n), v), 0.0), 80.0);
    color += vec3(1.0) * shine * 0.9;
    gl_FragColor = vec4(color, 1.0);
    #include <colorspace_fragment>
  }
`;

const orbMaterial = new THREE.ShaderMaterial({
  uniforms: { uTime: { value: 0 }, uCamera: { value: new THREE.Vector3() }, uLight: { value: new THREE.Vector3() } },
  vertexShader: ORB_VERTEX,
  fragmentShader: ORB_FRAGMENT,
  transparent: true,
  depthWrite: false,
  toneMapped: false,
});
const orb = new THREE.Mesh(new THREE.SphereGeometry(1, 96, 64), orbMaterial);
orb.renderOrder = 2;
scene.add(orb);

function glowTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 256;
  const g = canvas.getContext('2d');
  const gradient = g.createRadialGradient(128, 128, 0, 128, 128, 128);
  gradient.addColorStop(0, 'rgba(255, 186, 80, 0.7)');
  gradient.addColorStop(0.3, 'rgba(255, 170, 60, 0.22)');
  gradient.addColorStop(1, 'rgba(255, 160, 50, 0)');
  g.fillStyle = gradient;
  g.fillRect(0, 0, 256, 256);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}
const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTexture(), depthWrite: false, toneMapped: false }));
glow.renderOrder = 1;
scene.add(glow);

const orbLight = new THREE.PointLight(0xffaa44, 2, 1.6, 2);
scene.add(orbLight);

// The life tree inside the orb: stars joined to the nearest earlier ones, lit
// one after another as the page goes on.
function lifeTree(count = 84) {
  let seed = 7;
  const random = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;
  const points = [];
  for (let i = 0; i < count; i++) {
    const y = 1 - (2 * (i + 0.5)) / count;
    const ring = Math.sqrt(1 - y * y);
    const turn = i * Math.PI * (3 - Math.sqrt(5));
    const depth = 0.35 + 0.33 * random();
    points.push(new THREE.Vector3(Math.cos(turn) * ring, y, Math.sin(turn) * ring).multiplyScalar(depth));
  }
  // Grow outward from the middle: nearest the centre first.
  points.sort((a, b) => a.length() - b.length());
  const positions = [];
  const order = [];
  points.forEach((point, i) => {
    positions.push(point.x, point.y, point.z);
    order.push(i / count);
  });
  const lines = [];
  const lineOrder = [];
  for (let i = 1; i < count; i++) {
    const near = points
      .slice(0, i)
      .map((q, j) => [q.distanceTo(points[i]), j])
      .sort((a, b) => a[0] - b[0])
      .slice(0, i > 6 ? 2 : 1);
    for (const [, j] of near) {
      lines.push(points[i].x, points[i].y, points[i].z, points[j].x, points[j].y, points[j].z);
      lineOrder.push(i / count, i / count);
    }
  }
  const shown = { value: 0 };
  const starGeometry = new THREE.BufferGeometry();
  starGeometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  starGeometry.setAttribute('order', new THREE.Float32BufferAttribute(order, 1));
  const stars = new THREE.Points(
    starGeometry,
    new THREE.ShaderMaterial({
      uniforms: { uShown: shown, uScale: { value: 1 } },
      vertexShader: /* glsl */ `
        attribute float order;
        uniform float uShown;
        uniform float uScale;
        varying float vOn;
        void main() {
          vOn = smoothstep(order, order + 0.04, uShown);
          vec4 mv = modelViewMatrix * vec4(position, 1.0);
          gl_PointSize = uScale * (0.6 + 0.4 * vOn) / -mv.z;
          gl_Position = projectionMatrix * mv;
        }`,
      fragmentShader: /* glsl */ `
        varying float vOn;
        void main() {
          float d = length(gl_PointCoord - 0.5);
          float core = smoothstep(0.22, 0.12, d) + 0.5 * smoothstep(0.5, 0.0, d);
          vec3 color = mix(vec3(0.45, 0.16, 0.01), vec3(1.0, 1.0, 0.96), vOn);
          gl_FragColor = vec4(color, clamp(core, 0.0, 1.0) * (0.4 + 0.6 * vOn));
          #include <colorspace_fragment>
        }`,
      transparent: true,
      depthWrite: false,
      toneMapped: false,
    }),
  );
  const lineGeometry = new THREE.BufferGeometry();
  lineGeometry.setAttribute('position', new THREE.Float32BufferAttribute(lines, 3));
  lineGeometry.setAttribute('order', new THREE.Float32BufferAttribute(lineOrder, 1));
  const links = new THREE.LineSegments(
    lineGeometry,
    new THREE.ShaderMaterial({
      uniforms: { uShown: shown },
      vertexShader: /* glsl */ `
        attribute float order;
        uniform float uShown;
        varying float vOn;
        void main() {
          vOn = smoothstep(order, order + 0.04, uShown);
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }`,
      fragmentShader: /* glsl */ `
        varying float vOn;
        void main() {
          gl_FragColor = vec4(vec3(1.0, 0.98, 0.92), 0.95 * vOn);
          #include <colorspace_fragment>
        }`,
      transparent: true,
      depthWrite: false,
      toneMapped: false,
    }),
  );
  const tree = new THREE.Group();
  tree.add(links, stars);
  tree.renderOrder = 3;
  stars.renderOrder = 3;
  links.renderOrder = 3;
  return { tree, shown, stars };
}
const life = lifeTree();
scene.add(life.tree);

// ------------------------------------------------------------------ the robot

const lacquer = new THREE.MeshPhysicalMaterial({
  color: 0x060609,
  metalness: 0.15,
  roughness: 0.14,
  clearcoat: 1,
  clearcoatRoughness: 0.04,
  iridescence: 1,
  iridescenceIOR: 1.7,
  iridescenceThicknessRange: [260, 620],
  envMapIntensity: 1.25,
});
const joints = lacquer.clone();
joints.roughness = 0.32;
joints.color.set(0x0c0c12);

const v = (x, y, z) => new THREE.Vector3(x, y, z).normalize();
const lerpDir = (a, b, t) => a.clone().lerp(b, t).normalize();
const smooth = (a, b, x) => {
  const t = Math.min(Math.max((x - a) / (b - a), 0), 1);
  return t * t * (3 - 2 * t);
};

// The right arm at the start (cradling the orb at the collarbone) and at the
// end (reaching it up toward the camera), as world directions for a robot
// facing +z: its right is -x.
const POSE = {
  arm: [v(-0.22, -0.93, 0.2), v(-0.25, 0.32, 0.92)],
  forearm: [v(0.5, 0.55, 0.67), v(0.02, 0.42, 0.91)],
  hand: [v(0.6, 0.12, 0.79), v(0.08, 0.2, 0.98)],
  armNormal: [v(1, 0, 0), v(0, 1, 0)],
};
const UP = new THREE.Vector3(0, 1, 0);

let robot = null;

const _a = new THREE.Vector3();
const _b = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _m = new THREE.Matrix4();
const _n = new THREE.Matrix4();

// The world rotation taking a bone's rest direction and rest palm normal
// (both in its own frame) to [dir] and [normal].
function orient(restDir, restNormal, dir, normal) {
  const rn = restNormal.clone().addScaledVector(restDir, -restNormal.dot(restDir)).normalize();
  const tn = normal.clone().addScaledVector(dir, -normal.dot(dir)).normalize();
  _m.makeBasis(restDir, rn, _a.crossVectors(restDir, rn));
  _n.makeBasis(dir, tn, _b.crossVectors(dir, tn));
  return new THREE.Quaternion().setFromRotationMatrix(_n.multiply(_m.transpose()));
}

function setWorld(bone, worldQuaternion) {
  bone.parent.getWorldQuaternion(_q);
  bone.quaternion.copy(_q.invert().multiply(worldQuaternion));
  bone.updateMatrixWorld(true);
}

async function loadRobot() {
  const gltf = await new GLTFLoader().loadAsync('xbot.glb');
  const model = gltf.scene;
  model.traverse((o) => {
    if (o.isMesh) {
      o.castShadow = true;
      o.material = o.material.name.includes('Joints') ? joints : lacquer;
    }
  });
  scene.add(model);
  const bone = (name) => model.getObjectByName(`mixamorig${name}`) ?? model.getObjectByName(`mixamorig:${name}`);
  const world = (o) => o.getWorldPosition(new THREE.Vector3());

  // Face +z, toes forward.
  model.updateMatrixWorld(true);
  const toes = world(bone('RightToeBase')).sub(world(bone('RightFoot')));
  model.rotation.y = -Math.atan2(toes.x, toes.z);
  model.updateMatrixWorld(true);

  // Rest directions and palm normals (palms face down in the bind pose).
  const rest = {};
  const restOf = (name, child) => {
    const b = bone(name);
    const inverse = b.getWorldQuaternion(new THREE.Quaternion()).invert();
    rest[name] = {
      bone: b,
      dir: bone(child).position.clone().normalize(),
      normal: new THREE.Vector3(0, -1, 0).applyQuaternion(inverse),
    };
  };
  restOf('RightArm', 'RightForeArm');
  restOf('RightForeArm', 'RightHand');
  restOf('RightHand', 'RightHandMiddle1');
  const head = bone('Head');
  const headForward = new THREE.Vector3(0, 0, 1).applyQuaternion(head.getWorldQuaternion(new THREE.Quaternion()).invert());

  // Finger joints curl toward the palm to cradle the orb.
  const fingers = [];
  for (const finger of ['Index', 'Middle', 'Ring', 'Pinky', 'Thumb']) {
    for (const joint of [1, 2, 3]) {
      const b = bone(`RightHand${finger}${joint}`);
      const child = bone(`RightHand${finger}${joint + 1}`);
      if (!b || !child) continue;
      const inverse = b.getWorldQuaternion(new THREE.Quaternion()).invert();
      const dir = child.position.clone().normalize();
      const palm = new THREE.Vector3(0, -1, 0).applyQuaternion(inverse);
      const axis = new THREE.Vector3().crossVectors(dir, palm).normalize();
      fingers.push({ bone: b, axis, amount: finger === 'Thumb' ? 0.15 : 0.32 });
    }
  }

  const mixer = new THREE.AnimationMixer(model);
  const idle = gltf.animations.find((clip) => clip.name === 'idle');
  if (idle) mixer.clipAction(idle).play();

  const size = new THREE.Box3().setFromObject(model).getSize(new THREE.Vector3());
  robot = { model, bone, world, rest, head, headForward, fingers, mixer, height: size.y };
}

// Poses the arm for [t] (0 start, 1 raised) and puts the orb on the palm.
function pose(t) {
  const { rest, bone, world, head, headForward, fingers } = robot;
  const pick = (pair) => lerpDir(pair[0], pair[1], t);
  const handDir = pick(POSE.hand);

  setWorld(rest.RightArm.bone, orient(rest.RightArm.dir, rest.RightArm.normal, pick(POSE.arm), pick(POSE.armNormal)));
  setWorld(rest.RightForeArm.bone, orient(rest.RightForeArm.dir, rest.RightForeArm.normal, pick(POSE.forearm), UP));
  setWorld(rest.RightHand.bone, orient(rest.RightHand.dir, rest.RightHand.normal, handDir, UP));
  for (const f of fingers) {
    f.bone.quaternion.setFromAxisAngle(f.axis, f.amount);
  }
  robot.model.updateMatrixWorld(true);

  // On the palm: between the wrist and the knuckles, lifted by its radius.
  const radius = THREE.MathUtils.lerp(0.075, 0.16, t);
  const palm = world(bone('RightHand')).lerp(world(bone('RightHandMiddle1')), 0.7);
  const normal = UP.clone().addScaledVector(handDir, -UP.dot(handDir)).normalize();
  orb.position.copy(palm).addScaledVector(normal, radius * 1.02);
  orb.scale.setScalar(radius);
  glow.position.copy(orb.position);
  glow.scale.setScalar(radius * 3.4);
  orbLight.position.copy(orb.position);
  life.tree.position.copy(orb.position);
  life.tree.scale.setScalar(radius);
  orbLight.intensity = 0.5 + 2.5 * t;

  // The head looks down at the orb.
  const headWorld = head.getWorldQuaternion(new THREE.Quaternion());
  const facing = headForward.clone().applyQuaternion(headWorld);
  const toOrb = orb.position.clone().sub(world(head)).normalize();
  const turn = new THREE.Quaternion().setFromUnitVectors(facing, toOrb);
  setWorld(head, new THREE.Quaternion().slerp(turn, 0.55).multiply(headWorld));
}

// ------------------------------------------------------------------ the camera

// Per scroll stage 0..5: camera position, where it looks, and how far the
// picture shifts sideways (a fraction of the width; + moves the robot right).
const SHOTS = {
  wide: [
    { at: [0.35, 1.5, 1.95], look: [-0.05, 1.42, 0], shift: 0.2 },
    { at: [0.45, 1.85, 1.85], look: [-0.06, 1.38, 0.05], shift: 0.2 },
    { at: [0.38, 2.45, 1.6], look: [-0.08, 1.3, 0.12], shift: 0.2 },
    { at: [0.25, 3.0, 1.15], look: [-0.1, 1.2, 0.2], shift: 0.2 },
    { at: [0.12, 3.45, 0.7], look: [-0.12, 1.12, 0.26], shift: 0.2 },
    { at: [0.06, 3.3, 0.55], look: [-0.14, 1.12, 0.3], shift: 0.1 },
  ],
  narrow: [
    { at: [0.3, 1.45, 2.75], look: [-0.05, 1.36, 0], shift: -0.04, drop: 0.24 },
    { at: [0.45, 1.95, 2.6], look: [-0.06, 1.32, 0.05], shift: -0.04, drop: 0.24 },
    { at: [0.4, 2.8, 2.25], look: [-0.08, 1.26, 0.12], shift: -0.04, drop: 0.22 },
    { at: [0.28, 3.6, 1.6], look: [-0.1, 1.18, 0.2], shift: -0.04, drop: 0.2 },
    { at: [0.14, 4.3, 0.95], look: [-0.12, 1.1, 0.26], shift: -0.04, drop: 0.18 },
    { at: [0.08, 4.1, 0.8], look: [-0.13, 1.1, 0.3], shift: -0.04, drop: 0 },
  ],
};
const curves = {};
for (const [layout, shots] of Object.entries(SHOTS)) {
  curves[layout] = {
    at: new THREE.CatmullRomCurve3(shots.map((s) => new THREE.Vector3(...s.at))),
    look: new THREE.CatmullRomCurve3(shots.map((s) => new THREE.Vector3(...s.look))),
    shots,
  };
}

function placeCamera(p, width, height) {
  const layout = width >= 1024 ? 'wide' : 'narrow';
  const { at, look, shots } = curves[layout];
  const u = Math.min(Math.max(p, 0), 5) / 5;
  camera.position.copy(at.getPoint(u));
  camera.lookAt(look.getPoint(u));
  const i = Math.min(Math.floor(p), 4);
  const f = THREE.MathUtils.smoothstep(p - i, 0, 1);
  const shift = THREE.MathUtils.lerp(shots[i].shift, shots[i + 1].shift, f);
  const drop = THREE.MathUtils.lerp(shots[i].drop ?? 0, shots[i + 1].drop ?? 0, f);
  camera.fov = layout === 'wide' ? 30 : 40;
  camera.aspect = width / height;
  camera.setViewOffset(width, height, -shift * width, -drop * height, width, height);
  camera.updateProjectionMatrix();
}

// ------------------------------------------------------------------ the loop

function resize() {
  renderer.setSize(innerWidth, innerHeight, false);
  renderer.domElement.style.width = `${innerWidth}px`;
  renderer.domElement.style.height = `${innerHeight}px`;
}
addEventListener('resize', resize);
resize();

const clock = new THREE.Clock();
const _screen = new THREE.Vector3();
let lastSent = '';

function frame() {
  const dt = Math.min(clock.getDelta(), 0.05);
  progress += (target - progress) * Math.min(1, dt * 14);
  if (Math.abs(target - progress) < 1e-4) progress = target;
  orbMaterial.uniforms.uTime.value = clock.elapsedTime;

  robot.mixer.update(dt);
  pose(smooth(0.35, 4, progress));
  life.shown.value = 0.2 + 0.8 * smooth(0, 4, progress);
  life.tree.rotation.y = clock.elapsedTime * 0.12;
  life.stars.material.uniforms.uScale.value = 26 * renderer.getPixelRatio() * (innerHeight / 900);
  placeCamera(progress, innerWidth, innerHeight);
  camera.updateMatrixWorld();
  orbMaterial.uniforms.uCamera.value.copy(camera.position).sub(orb.position).divideScalar(orb.scale.x);
  orbMaterial.uniforms.uLight.value.copy(key.position).normalize().transformDirection(camera.matrixWorldInverse);
  // At the end the page's night covers everything: nothing to draw.
  if (progress < 4.98 || query.has('p')) renderer.render(scene, camera);

  // Where the orb is on screen, for the page.
  _screen.copy(orb.position).project(camera);
  const x = (_screen.x * 0.5 + 0.5) * innerWidth;
  const y = (-_screen.y * 0.5 + 0.5) * innerHeight;
  const distance = camera.position.distanceTo(orb.position);
  const focal = innerHeight / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2));
  const r = (orb.scale.x * focal) / distance;
  const message = `${x.toFixed(1)},${y.toFixed(1)},${r.toFixed(1)}`;
  if (message !== lastSent) {
    lastSent = message;
    post({ type: 'orb', x, y, r });
  }
  requestAnimationFrame(frame);
}

loadRobot()
  .then(() => {
    frame();
    if (query.has('p')) renderer.domElement.style.transition = 'none';
    renderer.domElement.classList.add('on');
    post({ type: 'ready' });
    document.documentElement.dataset.ready = 'true';
  })
  .catch((error) => {
    console.error(error);
    post({ type: 'unsupported' });
  });
