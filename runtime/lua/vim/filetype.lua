local api = vim.api
local fn = vim.fn

local M = {}

--- @alias vim.filetype.mapfn fun(path:string,bufnr:integer, ...):string?, fun(b:integer)?
--- @alias vim.filetype.mapopts { fastpat: string, priority: number }
--- @alias vim.filetype.maptbl [string|vim.filetype.mapfn, vim.filetype.mapopts]
--- @alias vim.filetype.mapping.value string|vim.filetype.mapfn|vim.filetype.maptbl
--- @alias vim.filetype.mapping table<string,vim.filetype.mapping.value>

--- @param ft string|vim.filetype.mapfn
--- @param opts? vim.filetype.mapopts
--- @return vim.filetype.maptbl
local function starsetf(ft, opts)
  return {
    function(path, bufnr)
      -- Note: when `ft` is a function its return value may be nil.
      local f = type(ft) ~= 'function' and ft or ft(path, bufnr)
      if not vim.g.ft_ignore_pat then
        return f
      end

      local re = vim.regex(vim.g.ft_ignore_pat)
      if not re:match_str(path) then
        return f
      end
    end,
    {
      -- Setting to "" by default essentially disables fast pattern (as "" matches any string)
      fastpat = (opts and opts.fastpat) or '',
      -- Starset matches should have lowest priority by default
      priority = (opts and opts.priority) or -math.huge,
    },
  }
end

---@private
--- Get a line range from the buffer.
---@param bufnr integer The buffer to get the lines from
---@param start_lnum integer|nil The line number of the first line (inclusive, 1-based)
---@param end_lnum integer|nil The line number of the last line (inclusive, 1-based)
---@return string[] # Array of lines
function M._getlines(bufnr, start_lnum, end_lnum)
  if start_lnum then
    return api.nvim_buf_get_lines(bufnr, start_lnum - 1, end_lnum or start_lnum, false)
  end

  -- Return all lines
  return api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---@private
--- Get a single line from the buffer.
---@param bufnr integer The buffer to get the lines from
---@param start_lnum integer The line number of the first line (inclusive, 1-based)
---@return string
function M._getline(bufnr, start_lnum)
  -- Return a single line
  return api.nvim_buf_get_lines(bufnr, start_lnum - 1, start_lnum, false)[1] or ''
end

---@private
--- Check whether a string matches any of the given Lua patterns.
---
---@param s string? The string to check
---@param patterns string[] A list of Lua patterns
---@return boolean `true` if s matched a pattern, else `false`
function M._findany(s, patterns)
  if not s then
    return false
  end
  for _, v in ipairs(patterns) do
    if s:find(v) then
      return true
    end
  end
  return false
end

---@private
--- Get the next non-whitespace line in the buffer.
---
---@param bufnr integer The buffer to get the line from
---@param start_lnum integer The line number of the first line to start from (inclusive, 1-based)
---@return string|nil The first non-blank line if found or `nil` otherwise
function M._nextnonblank(bufnr, start_lnum)
  for _, line in ipairs(M._getlines(bufnr, start_lnum, -1)) do
    if not line:find('^%s*$') then
      return line
    end
  end
  return nil
end

do
  --- @type table<string,vim.regex>
  local regex_cache = {}

  ---@private
  --- Check whether the given string matches the Vim regex pattern.
  --- @param s string?
  --- @param pattern string
  --- @return boolean
  function M._matchregex(s, pattern)
    if not s then
      return false
    end
    if not regex_cache[pattern] then
      regex_cache[pattern] = vim.regex(pattern)
    end
    return regex_cache[pattern]:match_str(s) ~= nil
  end
end

--- @module 'vim.filetype.detect'
local detect = setmetatable({}, {
  --- @param k string
  --- @param t table<string,function>
  --- @return function
  __index = function(t, k)
    t[k] = function(...)
      return require('vim.filetype.detect')[k](...)
    end
    return t[k]
  end,
})

--- @param ... string|vim.filetype.mapfn
--- @return vim.filetype.mapfn
local function detect_seq(...)
  local candidates = { ... }
  return function(...)
    for _, c in ipairs(candidates) do
      if type(c) == 'string' then
        return c
      end
      if type(c) == 'function' then
        local r = c(...)
        if r then
          return r
        end
      end
    end
  end
end

local function detect_noext(path, bufnr)
  local root = fn.fnamemodify(path, ':r')
  return M.match({ buf = bufnr, filename = root })
end

--- @param pat string
--- @param a string?
--- @param b string?
--- @return vim.filetype.mapfn
local function detect_line1(pat, a, b)
  return function(_path, bufnr)
    if M._getline(bufnr, 1):find(pat) then
      return a
    end
    return b
  end
end

--- @type vim.filetype.mapfn
local detect_rc = function(path, _bufnr)
  if not path:find('/etc/Muttrc%.d/') then
    return 'rc'
  end
end

-- luacheck: push no unused args
-- luacheck: push ignore 122

-- Filetypes based on file extension
---@diagnostic disable: unused-local
--- @type vim.filetype.mapping
local extension = {
  -- BEGIN EXTENSION
  ['8th'] = '8th',
  a65 = 'a65',
  aap = 'aap',
  abap = 'abap',
  abc = 'abc',
  abl = 'abel',
  wrm = 'acedb',
  ads = 'ada',
  ada = 'ada',
  gpr = 'ada',
  adb = 'ada',
  tdf = 'ahdl',
  aidl = 'aidl',
  aml = 'aml',
  run = 'ampl',
  scpt = 'applescript',
  ino = 'arduino',
  pde = 'arduino',
  art = 'art',
  asciidoc = 'asciidoc',
  adoc = 'asciidoc',
  asa = function(path, bufnr)
    if vim.g.filetype_asa then
      return vim.g.filetype_asa
    end
    return 'aspvbs'
  end,
  asm = detect.asm,
  s = detect.asm,
  S = detect.asm,
  a = detect.asm,
  A = detect.asm,
  lst = detect.asm,
  mac = detect.asm,
  asn1 = 'asn',
  asn = 'asn',
  asp = detect.asp,
  astro = 'astro',
  atl = 'atlas',
  as = 'atlas',
  zed = 'authzed',
  ahk = 'autohotkey',
  au3 = 'autoit',
  ave = 'ave',
  gawk = 'awk',
  awk = 'awk',
  ref = 'b',
  imp = 'b',
  mch = 'b',
  bas = detect.bas,
  bass = 'bass',
  bi = detect.bas,
  bm = detect.bas,
  bc = 'bc',
  bdf = 'bdf',
  beancount = 'beancount',
  bib = 'bib',
  com = detect_seq(detect.bindzone, 'dcl'),
  db = detect.bindzone,
  bicep = 'bicep',
  bicepparam = 'bicep',
  zone = 'bindzone',
  bb = 'bitbake',
  bbappend = 'bitbake',
  bbclass = 'bitbake',
  bl = 'blank',
  blp = 'blueprint',
  bp = 'bp',
  bsd = 'bsdl',
  bsdl = 'bsdl',
  bst = 'bst',
  btm = function(path, bufnr)
    return (vim.g.dosbatch_syntax_for_btm and vim.g.dosbatch_syntax_for_btm ~= 0) and 'dosbatch'
      or 'btm'
  end,
  bzl = 'bzl',
  bazel = 'bzl',
  BUILD = 'bzl',
  mdh = 'c',
  epro = 'c',
  qc = 'c',
  cabal = 'cabal',
  cairo = 'cairo',
  capnp = 'capnp',
  cdc = 'cdc',
  cdl = 'cdl',
  toc = detect_line1('\\contentsline', 'tex', 'cdrtoc'),
  cedar = 'cedar',
  cfc = 'cf',
  cfm = 'cf',
  cfi = 'cf',
  hgrc = 'cfg',
  chf = 'ch',
  chai = 'chaiscript',
  ch = detect.change,
  chs = 'chaskell',
  chatito = 'chatito',
  chopro = 'chordpro',
  crd = 'chordpro',
  crdpro = 'chordpro',
  cho = 'chordpro',
  chordpro = 'chordpro',
  ck = 'chuck',
  eni = 'cl',
  icl = 'clean',
  cljx = 'clojure',
  clj = 'clojure',
  cljc = 'clojure',
  cljs = 'clojure',
  cook = 'cook',
  cmake = 'cmake',
  cmod = 'cmod',
  cob = 'cobol',
  cbl = 'cobol',
  atg = 'coco',
  recipe = 'conaryrecipe',
  ctags = 'conf',
  hook = function(path, bufnr)
    return M._getline(bufnr, 1) == '[Trigger]' and 'confini' or nil
  end,
  nmconnection = 'confini',
  mklx = 'context',
  mkiv = 'context',
  mkii = 'context',
  mkxl = 'context',
  mkvi = 'context',
  control = detect.control,
  copyright = detect.copyright,
  corn = 'corn',
  csh = detect.csh,
  cpon = 'cpon',
  moc = 'cpp',
  hh = 'cpp',
  tlh = 'cpp',
  inl = 'cpp',
  ipp = 'cpp',
  ['c++'] = 'cpp',
  C = 'cpp',
  cxx = 'cpp',
  H = 'cpp',
  tcc = 'cpp',
  hxx = 'cpp',
  hpp = 'cpp',
  ccm = 'cpp',
  cppm = 'cpp',
  cxxm = 'cpp',
  ['c++m'] = 'cpp',
  cpp = detect.cpp,
  cc = detect.cpp,
  cql = 'cqlang',
  crm = 'crm',
  cr = 'crystal',
  csx = 'cs',
  cs = 'cs',
  csc = 'csc',
  csdl = 'csdl',
  cshtml = 'html',
  fdr = 'csp',
  csp = 'csp',
  css = 'css',
  csv = 'csv',
  con = 'cterm',
  feature = 'cucumber',
  cuh = 'cuda',
  cu = 'cuda',
  cue = 'cue',
  pld = 'cupl',
  si = 'cuplsim',
  cyn = 'cynpp',
  cypher = 'cypher',
  dfy = 'dafny',
  dart = 'dart',
  drt = 'dart',
  ds = 'datascript',
  dcd = 'dcd',
  decl = detect.decl,
  dec = detect.decl,
  dcl = detect_seq(detect.decl, 'clean'),
  def = detect.def,
  desc = 'desc',
  directory = 'desktop',
  desktop = 'desktop',
  dhall = 'dhall',
  diff = 'diff',
  rej = 'diff',
  Dockerfile = 'dockerfile',
  dockerfile = 'dockerfile',
  bat = 'dosbatch',
  wrap = 'dosini',
  ini = 'dosini',
  INI = 'dosini',
  vbp = 'dosini',
  dot = 'dot',
  gv = 'dot',
  drac = 'dracula',
  drc = 'dracula',
  dsp = detect.dsp,
  dtd = 'dtd',
  d = detect.dtrace,
  dts = 'dts',
  dtsi = 'dts',
  dtso = 'dts',
  its = 'dts',
  keymap = 'dts',
  dylan = 'dylan',
  intr = 'dylanintr',
  lid = 'dylanlid',
  e = detect.e,
  E = detect.e,
  ecd = 'ecd',
  edf = 'edif',
  edif = 'edif',
  edo = 'edif',
  edn = detect.edn,
  eex = 'eelixir',
  leex = 'eelixir',
  am = 'elf',
  exs = 'elixir',
  elm = 'elm',
  lc = 'elsa',
  elv = 'elvish',
  ent = detect.ent,
  epp = 'epuppet',
  erl = 'erlang',
  hrl = 'erlang',
  yaws = 'erlang',
  erb = 'eruby',
  rhtml = 'eruby',
  esdl = 'esdl',
  ec = 'esqlc',
  EC = 'esqlc',
  strl = 'esterel',
  eu = detect.euphoria,
  EU = detect.euphoria,
  ew = detect.euphoria,
  EW = detect.euphoria,
  EX = detect.euphoria,
  exu = detect.euphoria,
  EXU = detect.euphoria,
  exw = detect.euphoria,
  EXW = detect.euphoria,
  ex = detect.ex,
  exp = 'expect',
  f = detect.f,
  factor = 'factor',
  fal = 'falcon',
  fan = 'fan',
  fwt = 'fan',
  lib = 'faust',
  fnl = 'fennel',
  m4gl = 'fgl',
  ['4gl'] = 'fgl',
  ['4gh'] = 'fgl',
  fir = 'firrtl',
  fish = 'fish',
  focexec = 'focexec',
  fex = 'focexec',
  ft = 'forth',
  fth = 'forth',
  ['4th'] = 'forth',
  FOR = 'fortran',
  f77 = 'fortran',
  f03 = 'fortran',
  fortran = 'fortran',
  F95 = 'fortran',
  f90 = 'fortran',
  F03 = 'fortran',
  fpp = 'fortran',
  FTN = 'fortran',
  ftn = 'fortran',
  ['for'] = 'fortran',
  F90 = 'fortran',
  F77 = 'fortran',
  f95 = 'fortran',
  FPP = 'fortran',
  F = 'fortran',
  F08 = 'fortran',
  f08 = 'fortran',
  fpc = 'fpcmake',
  fsl = 'framescript',
  frm = detect.frm,
  fb = 'freebasic',
  fs = detect.fs,
  fsh = 'fsh',
  fsi = 'fsharp',
  fsx = 'fsharp',
  fc = 'func',
  fusion = 'fusion',
  gdb = 'gdb',
  gdmo = 'gdmo',
  mo = 'gdmo',
  tscn = 'gdresource',
  tres = 'gdresource',
  gd = 'gdscript',
  gdshader = 'gdshader',
  shader = 'gdshader',
  ged = 'gedcom',
  gmi = 'gemtext',
  gemini = 'gemtext',
  gift = 'gift',
  prettierignore = 'gitignore',
  gleam = 'gleam',
  glsl = 'glsl',
  gn = 'gn',
  gni = 'gn',
  gnuplot = 'gnuplot',
  gpi = 'gnuplot',
  go = 'go',
  gp = 'gp',
  gs = 'grads',
  gql = 'graphql',
  graphql = 'graphql',
  graphqls = 'graphql',
  gretl = 'gretl',
  gradle = 'groovy',
  groovy = 'groovy',
  gsp = 'gsp',
  gjs = 'javascript.glimmer',
  gts = 'typescript.glimmer',
  gyp = 'gyp',
  gypi = 'gyp',
  hack = 'hack',
  hackpartial = 'hack',
  haml = 'haml',
  hsm = 'hamster',
  hbs = 'handlebars',
  ha = 'hare',
  ['hs-boot'] = 'haskell',
  hsig = 'haskell',
  hsc = 'haskell',
  hs = 'haskell',
  persistentmodels = 'haskellpersistent',
  ht = 'haste',
  htpp = 'hastepreproc',
  hcl = 'hcl',
  hb = 'hb',
  h = detect.header,
  sum = 'hercules',
  errsum = 'hercules',
  ev = 'hercules',
  vc = 'hercules',
  heex = 'heex',
  hex = 'hex',
  ['a43'] = 'hex',
  ['a90'] = 'hex',
  ['h32'] = 'hex',
  ['h80'] = 'hex',
  ['h86'] = 'hex',
  ihex = 'hex',
  ihe = 'hex',
  ihx = 'hex',
  int = 'hex',
  mcs = 'hex',
  hjson = 'hjson',
  m3u = 'hlsplaylist',
  m3u8 = 'hlsplaylist',
  hog = 'hog',
  hws = 'hollywood',
  hoon = 'hoon',
  cpt = detect.html,
  dtml = detect.html,
  htm = detect.html,
  html = detect.html,
  pt = detect.html,
  shtml = detect.html,
  stm = detect.html,
  htt = 'httest',
  htb = 'httest',
  hurl = 'hurl',
  hw = detect.hw,
  module = detect.hw,
  pkg = detect.hw,
  iba = 'ibasic',
  ibi = 'ibasic',
  icn = 'icon',
  idl = detect.idl,
  inc = detect.inc,
  inf = 'inform',
  INF = 'inform',
  ii = 'initng',
  inko = 'inko',
  inp = detect.inp,
  ms = detect_seq(detect.nroff, 'xmath'),
  iss = 'iss',
  mst = 'ist',
  ist = 'ist',
  ijs = 'j',
  JAL = 'jal',
  jal = 'jal',
  jpr = 'jam',
  jpl = 'jam',
  janet = 'janet',
  jav = 'java',
  java = 'java',
  jj = 'javacc',
  jjt = 'javacc',
  es = 'javascript',
  mjs = 'javascript',
  javascript = 'javascript',
  js = 'javascript',
  jsm = 'javascript',
  cjs = 'javascript',
  jsx = 'javascriptreact',
  clp = 'jess',
  jgr = 'jgraph',
  jjdescription = 'jj',
  j73 = 'jovial',
  jov = 'jovial',
  jovial = 'jovial',
  properties = 'jproperties',
  jq = 'jq',
  slnf = 'json',
  json = 'json',
  jsonp = 'json',
  geojson = 'json',
  webmanifest = 'json',
  ipynb = 'json',
  ['jupyterlab-settings'] = 'json',
  ['sublime-project'] = 'json',
  ['sublime-settings'] = 'json',
  ['sublime-workspace'] = 'json',
  ['json-patch'] = 'json',
  bd = 'json',
  bda = 'json',
  xci = 'json',
  json5 = 'json5',
  jsonc = 'jsonc',
  jsonl = 'jsonl',
  jsonnet = 'jsonnet',
  libsonnet = 'jsonnet',
  jsp = 'jsp',
  jl = 'julia',
  just = 'just',
  kdl = 'kdl',
  kv = 'kivy',
  kix = 'kix',
  kts = 'kotlin',
  kt = 'kotlin',
  ktm = 'kotlin',
  ks = 'kscript',
  k = 'kwt',
  ACE = 'lace',
  ace = 'lace',
  latte = 'latte',
  lte = 'latte',
  ld = 'ld',
  ldif = 'ldif',
  lean = 'lean',
  journal = 'ledger',
  ldg = 'ledger',
  ledger = 'ledger',
  less = 'less',
  lex = 'lex',
  lxx = 'lex',
  ['l++'] = 'lex',
  l = 'lex',
  lhs = 'lhaskell',
  ll = 'lifelines',
  ly = 'lilypond',
  ily = 'lilypond',
  liquid = 'liquid',
  liq = 'liquidsoap',
  cl = 'lisp',
  L = 'lisp',
  lisp = 'lisp',
  el = 'lisp',
  lsp = 'lisp',
  asd = 'lisp',
  stsg = 'lisp',
  lt = 'lite',
  lite = 'lite',
  livemd = 'livebook',
  lgt = 'logtalk',
  lotos = 'lotos',
  lot = detect_line1('\\contentsline', 'tex', 'lotos'),
  lout = 'lout',
  lou = 'lout',
  ulpc = 'lpc',
  lpc = 'lpc',
  c = detect.lpc,
  lsl = detect.lsl,
  lss = 'lss',
  nse = 'lua',
  rockspec = 'lua',
  lua = 'lua',
  tlu = 'lua',
  luau = 'luau',
  lrc = 'lyrics',
  m = detect.m,
  at = 'm4',
  mc = detect.mc,
  quake = 'm3quake',
  m4 = function(path, bufnr)
    path = path:lower()
    return not (path:find('html%.m4$') or path:find('fvwm2rc')) and 'm4' or nil
  end,
  eml = 'mail',
  mk = 'make',
  mak = 'make',
  page = 'mallard',
  map = 'map',
  mws = 'maple',
  mpl = 'maple',
  mv = 'maple',
  mkdn = detect.markdown,
  md = detect.markdown,
  mdwn = detect.markdown,
  mkd = detect.markdown,
  markdown = detect.markdown,
  mdown = detect.markdown,
  mhtml = 'mason',
  comp = 'mason',
  mason = 'mason',
  master = 'master',
  mas = 'master',
  demo = 'maxima',
  dm1 = 'maxima',
  dm2 = 'maxima',
  dm3 = 'maxima',
  dmt = 'maxima',
  wxm = 'maxima',
  mel = 'mel',
  mmd = 'mermaid',
  mmdc = 'mermaid',
  mermaid = 'mermaid',
  mf = 'mf',
  mgl = 'mgl',
  mgp = 'mgp',
  my = 'mib',
  mib = 'mib',
  mix = 'mix',
  mixal = 'mix',
  mm = detect.mm,
  nb = 'mma',
  mmp = 'mmp',
  mms = detect.mms,
  DEF = 'modula2',
  m3 = 'modula3',
  i3 = 'modula3',
  mg = 'modula3',
  ig = 'modula3',
  lm3 = 'modula3',
  mojo = 'mojo',
  ['🔥'] = 'mojo', -- 🙄
  ssc = 'monk',
  monk = 'monk',
  tsc = 'monk',
  isc = 'monk',
  moo = 'moo',
  moon = 'moonscript',
  move = 'move',
  mp = 'mp',
  mpiv = detect.mp,
  mpvi = detect.mp,
  mpxl = detect.mp,
  mof = 'msidl',
  odl = 'msidl',
  msql = 'msql',
  mu = 'mupad',
  mush = 'mush',
  mustache = 'mustache',
  mysql = 'mysql',
  n1ql = 'n1ql',
  nql = 'n1ql',
  nanorc = 'nanorc',
  ncf = 'ncf',
  nginx = 'nginx',
  nim = 'nim',
  nims = 'nim',
  nimble = 'nim',
  ninja = 'ninja',
  nix = 'nix',
  norg = 'norg',
  nqc = 'nqc',
  roff = 'nroff',
  tmac = 'nroff',
  man = 'nroff',
  mom = 'nroff',
  nr = 'nroff',
  tr = 'nroff',
  nsi = 'nsis',
  nsh = 'nsis',
  nu = 'nu',
  obj = 'obj',
  objdump = 'objdump',
  cppobjdump = 'objdump',
  obl = 'obse',
  obse = 'obse',
  oblivion = 'obse',
  obscript = 'obse',
  mlt = 'ocaml',
  mly = 'ocaml',
  mll = 'ocaml',
  mlp = 'ocaml',
  mlip = 'ocaml',
  mli = 'ocaml',
  ml = 'ocaml',
  occ = 'occam',
  odin = 'odin',
  xom = 'omnimark',
  xin = 'omnimark',
  opam = 'opam',
  ['or'] = 'openroad',
  scad = 'openscad',
  ovpn = 'openvpn',
  ora = 'ora',
  org = 'org',
  org_archive = 'org',
  pandoc = 'pandoc',
  pdk = 'pandoc',
  pd = 'pandoc',
  pdc = 'pandoc',
  pxsl = 'papp',
  papp = 'papp',
  pxml = 'papp',
  pas = 'pascal',
  lpr = detect_line1('<%?xml', 'xml', 'pascal'),
  dpr = 'pascal',
  txtpb = 'pbtxt',
  textproto = 'pbtxt',
  textpb = 'pbtxt',
  pbtxt = 'pbtxt',
  g = 'pccts',
  pcmk = 'pcmk',
  pdf = 'pdf',
  pem = 'pem',
  cer = 'pem',
  crt = 'pem',
  csr = 'pem',
  plx = 'perl',
  prisma = 'prisma',
  psgi = 'perl',
  al = 'perl',
  ctp = 'php',
  php = 'php',
  phpt = 'php',
  phtml = 'php',
  theme = 'php',
  pike = 'pike',
  pmod = 'pike',
  rcp = 'pilrc',
  PL = detect.pl,
  pli = 'pli',
  pl1 = 'pli',
  p36 = 'plm',
  plm = 'plm',
  pac = 'plm',
  plp = 'plp',
  pls = 'plsql',
  plsql = 'plsql',
  po = 'po',
  pot = 'po',
  pod = 'pod',
  filter = 'poefilter',
  pk = 'poke',
  pony = 'pony',
  ps = 'postscr',
  epsi = 'postscr',
  afm = 'postscr',
  epsf = 'postscr',
  eps = 'postscr',
  pfa = 'postscr',
  ai = 'postscr',
  pov = 'pov',
  ppd = 'ppd',
  it = 'ppwiz',
  ih = 'ppwiz',
  action = 'privoxy',
  pc = 'proc',
  pdb = 'prolog',
  pml = 'promela',
  proto = 'proto',
  prql = 'prql',
  psd1 = 'ps1',
  psm1 = 'ps1',
  ps1 = 'ps1',
  pssc = 'ps1',
  ps1xml = 'ps1xml',
  psf = 'psf',
  psl = 'psl',
  pug = 'pug',
  purs = 'purescript',
  arr = 'pyret',
  pxd = 'pyrex',
  pyx = 'pyrex',
  pyw = 'python',
  py = 'python',
  pyi = 'python',
  ptl = 'python',
  ql = 'ql',
  qll = 'ql',
  qml = 'qml',
  qbs = 'qml',
  qmd = 'quarto',
  R = detect.r,
  rkt = 'racket',
  rktd = 'racket',
  rktl = 'racket',
  rad = 'radiance',
  mat = 'radiance',
  pod6 = 'raku',
  rakudoc = 'raku',
  rakutest = 'raku',
  rakumod = 'raku',
  pm6 = 'raku',
  raku = 'raku',
  t6 = 'raku',
  p6 = 'raku',
  raml = 'raml',
  rasi = 'rasi',
  rbs = 'rbs',
  rego = 'rego',
  rem = 'remind',
  remind = 'remind',
  pip = 'requirements',
  res = 'rescript',
  resi = 'rescript',
  frt = 'reva',
  testUnit = 'rexx',
  rex = 'rexx',
  orx = 'rexx',
  rexx = 'rexx',
  jrexx = 'rexx',
  rxj = 'rexx',
  rexxj = 'rexx',
  testGroup = 'rexx',
  rxo = 'rexx',
  Rd = 'rhelp',
  rd = 'rhelp',
  rib = 'rib',
  Rmd = 'rmd',
  rmd = 'rmd',
  smd = 'rmd',
  Smd = 'rmd',
  rnc = 'rnc',
  rng = 'rng',
  rnw = 'rnoweb',
  snw = 'rnoweb',
  Rnw = 'rnoweb',
  Snw = 'rnoweb',
  robot = 'robot',
  resource = 'robot',
  roc = 'roc',
  ron = 'ron',
  rsc = 'routeros',
  x = 'rpcgen',
  rpgle = 'rpgle',
  rpgleinc = 'rpgle',
  rpl = 'rpl',
  Srst = 'rrst',
  srst = 'rrst',
  Rrst = 'rrst',
  rrst = 'rrst',
  rst = 'rst',
  rtf = 'rtf',
  rjs = 'ruby',
  rxml = 'ruby',
  rb = 'ruby',
  rant = 'ruby',
  ru = 'ruby',
  rbw = 'ruby',
  gemspec = 'ruby',
  builder = 'ruby',
  rake = 'ruby',
  rs = 'rust',
  sage = 'sage',
  sas = 'sas',
  sass = 'sass',
  sa = 'sather',
  sbt = 'sbt',
  scala = 'scala',
  ss = 'scheme',
  scm = 'scheme',
  sld = 'scheme',
  sce = 'scilab',
  sci = 'scilab',
  scss = 'scss',
  sd = 'sd',
  sdc = 'sdc',
  pr = 'sdl',
  sdl = 'sdl',
  sed = 'sed',
  sexp = 'sexplib',
  bash = detect.bash,
  bats = detect.bash,
  cygport = detect.bash,
  ebuild = detect.bash,
  eclass = detect.bash,
  env = detect.sh,
  envrc = detect.sh,
  ksh = detect.ksh,
  sh = detect.sh,
  mdd = 'sh',
  sieve = 'sieve',
  siv = 'sieve',
  sig = detect.sig,
  sil = detect.sil,
  sim = 'simula',
  s85 = 'sinda',
  sin = 'sinda',
  ssm = 'sisu',
  sst = 'sisu',
  ssi = 'sisu',
  ['_sst'] = 'sisu',
  ['-sst'] = 'sisu',
  il = 'skill',
  ils = 'skill',
  cdf = 'skill',
  sl = 'slang',
  ice = 'slice',
  slint = 'slint',
  score = 'slrnsc',
  sol = 'solidity',
  smali = 'smali',
  tpl = 'smarty',
  ihlp = 'smcl',
  smcl = 'smcl',
  hlp = 'smcl',
  smith = 'smith',
  smt = 'smith',
  smithy = 'smithy',
  sml = 'sml',
  smk = 'snakemake',
  spt = 'snobol4',
  sno = 'snobol4',
  sln = 'solution',
  sparql = 'sparql',
  rq = 'sparql',
  spec = 'spec',
  spice = 'spice',
  sp = 'spice',
  spd = 'spup',
  spdata = 'spup',
  speedup = 'spup',
  spi = 'spyce',
  spy = 'spyce',
  tyc = 'sql',
  typ = detect.typ,
  pkb = 'sql',
  tyb = 'sql',
  pks = 'sql',
  sqlj = 'sqlj',
  sqi = 'sqr',
  sqr = 'sqr',
  nut = 'squirrel',
  s28 = 'srec',
  s37 = 'srec',
  srec = 'srec',
  mot = 'srec',
  s19 = 'srec',
  srt = 'srt',
  ssa = 'ssa',
  ass = 'ssa',
  st = 'st',
  ipd = 'starlark',
  star = 'starlark',
  starlark = 'starlark',
  imata = 'stata',
  ['do'] = 'stata',
  mata = 'stata',
  ado = 'stata',
  stp = 'stp',
  styl = 'stylus',
  stylus = 'stylus',
  quark = 'supercollider',
  sface = 'surface',
  svelte = 'svelte',
  svg = 'svg',
  swift = 'swift',
  swig = 'swig',
  swg = 'swig',
  svh = 'systemverilog',
  sv = 'systemverilog',
  cmm = 'trace32',
  t32 = 'trace32',
  td = 'tablegen',
  tak = 'tak',
  tal = 'tal',
  task = 'taskedit',
  tm = 'tcl',
  tcl = 'tcl',
  itk = 'tcl',
  itcl = 'tcl',
  tk = 'tcl',
  jacl = 'tcl',
  tl = 'teal',
  templ = 'templ',
  tmpl = 'template',
  ti = 'terminfo',
  dtx = 'tex',
  ltx = 'tex',
  bbl = 'tex',
  latex = 'tex',
  sty = 'tex',
  pgf = 'tex',
  nlo = 'tex',
  nls = 'tex',
  thm = 'tex',
  eps_tex = 'tex',
  pygtex = 'tex',
  pygstyle = 'tex',
  clo = 'tex',
  aux = 'tex',
  brf = 'tex',
  ind = 'tex',
  lof = 'tex',
  loe = 'tex',
  nav = 'tex',
  vrb = 'tex',
  ins = 'tex',
  tikz = 'tex',
  bbx = 'tex',
  cbx = 'tex',
  beamer = 'tex',
  cls = detect.cls,
  texi = 'texinfo',
  txi = 'texinfo',
  texinfo = 'texinfo',
  text = 'text',
  tfvars = 'terraform-vars',
  thrift = 'thrift',
  tla = 'tla',
  tli = 'tli',
  toml = 'toml',
  tpp = 'tpp',
  treetop = 'treetop',
  slt = 'tsalt',
  tsscl = 'tsscl',
  tssgm = 'tssgm',
  tssop = 'tssop',
  tsv = 'tsv',
  tutor = 'tutor',
  twig = 'twig',
  ts = detect_line1('<%?xml', 'xml', 'typescript'),
  mts = 'typescript',
  cts = 'typescript',
  tsx = 'typescriptreact',
  tsp = 'typespec',
  uc = 'uc',
  uit = 'uil',
  uil = 'uil',
  ungram = 'ungrammar',
  u = 'unison',
  uu = 'unison',
  url = 'urlshortcut',
  usd = 'usd',
  usda = 'usd',
  v = detect.v,
  vsh = 'v',
  vv = 'v',
  ctl = 'vb',
  dob = 'vb',
  dsm = 'vb',
  dsr = 'vb',
  pag = 'vb',
  sba = 'vb',
  vb = 'vb',
  vbs = 'vb',
  vba = detect.vba,
  vdf = 'vdf',
  vdmpp = 'vdmpp',
  vpp = 'vdmpp',
  vdmrt = 'vdmrt',
  vdmsl = 'vdmsl',
  vdm = 'vdmsl',
  vto = 'vento',
  vr = 'vera',
  vri = 'vera',
  vrh = 'vera',
  va = 'verilogams',
  vams = 'verilogams',
  vhdl = 'vhdl',
  vst = 'vhdl',
  vhd = 'vhdl',
  hdl = 'vhdl',
  vho = 'vhdl',
  vbe = 'vhdl',
  tape = 'vhs',
  vim = 'vim',
  mar = 'vmasm',
  cm = 'voscm',
  wrl = 'vrml',
  vroom = 'vroom',
  vue = 'vue',
  wast = 'wat',
  wat = 'wat',
  wdl = 'wdl',
  wm = 'webmacro',
  wgsl = 'wgsl',
  wbt = 'winbatch',
  wit = 'wit',
  wml = 'wml',
  wsf = 'wsh',
  wsc = 'wsh',
  wsml = 'wsml',
  ad = 'xdefaults',
  xhtml = 'xhtml',
  xht = 'xhtml',
  msc = 'xmath',
  msf = 'xmath',
  psc1 = 'xml',
  tpm = 'xml',
  xliff = 'xml',
  atom = 'xml',
  xul = 'xml',
  cdxml = 'xml',
  mpd = 'xml',
  rss = 'xml',
  fsproj = 'xml',
  ui = 'xml',
  vbproj = 'xml',
  xlf = 'xml',
  wsdl = 'xml',
  csproj = 'xml',
  wpl = 'xml',
  xmi = 'xml',
  xpr = 'xml',
  xpfm = 'xml',
  spfm = 'xml',
  bxml = 'xml',
  xcu = 'xml',
  xlb = 'xml',
  xlc = 'xml',
  xba = 'xml',
  xpm = detect_line1('XPM2', 'xpm2', 'xpm'),
  xpm2 = 'xpm2',
  xqy = 'xquery',
  xqm = 'xquery',
  xquery = 'xquery',
  xq = 'xquery',
  xql = 'xquery',
  xs = 'xs',
  xsd = 'xsd',
  xsl = 'xslt',
  xslt = 'xslt',
  yy = 'yacc',
  ['y++'] = 'yacc',
  yxx = 'yacc',
  yml = 'yaml',
  yaml = 'yaml',
  eyaml = 'yaml',
  mplstyle = 'yaml',
  yang = 'yang',
  yuck = 'yuck',
  z8a = 'z8a',
  zig = 'zig',
  zon = 'zig',
  zu = 'zimbu',
  zut = 'zimbutempl',
  zs = 'zserio',
  zsh = 'zsh',
  zunit = 'zsh',
  ['zsh-theme'] = 'zsh',
  vala = 'vala',
  web = detect.web,
  pl = detect.pl,
  pp = detect.pp,
  i = detect.i,
  w = detect.progress_cweb,
  p = detect.progress_pascal,
  pro = detect_seq(detect.proto, 'idlang'),
  patch = detect.patch,
  r = detect.r,
  rdf = detect.redif,
  rules = detect.rules,
  sc = detect.sc,
  scd = detect.scd,
  tcsh = function(path, bufnr)
    return require('vim.filetype.detect').shell(path, M._getlines(bufnr), 'tcsh')
  end,
  sql = detect.sql,
  zsql = detect.sql,
  tex = detect.tex,
  tf = detect.tf,
  txt = detect.txt,
  xml = detect.xml,
  y = detect.y,
  cmd = detect_line1('^/%*', 'rexx', 'dosbatch'),
  rul = detect.rul,
  cpy = detect_line1('^##', 'python', 'cobol'),
  dsl = detect_line1('^%s*<!', 'dsl', 'structurizr'),
  smil = detect_line1('<%?%s*xml.*%?>', 'xml', 'smil'),
  smi = detect.smi,
  install = detect.install,
  pm = detect.pm,
  me = detect.me,
  reg = detect.reg,
  ttl = detect.ttl,
  rc = detect_rc,
  rch = detect_rc,
  class = detect.class,
  sgml = detect.sgml,
  sgm = detect.sgml,
  t = detect_seq(detect.nroff, detect.perl, 'tads'),
  -- Ignored extensions
  bak = detect_noext,
  ['dpkg-bak'] = detect_noext,
  ['dpkg-dist'] = detect_noext,
  ['dpkg-old'] = detect_noext,
  ['dpkg-new'] = detect_noext,
  ['in'] = function(path, bufnr)
    if vim.fs.basename(path) ~= 'configure.in' then
      local root = fn.fnamemodify(path, ':r')
      return M.match({ buf = bufnr, filename = root })
    end
  end,
  new = detect_noext,
  old = detect_noext,
  orig = detect_noext,
  pacsave = detect_noext,
  pacnew = detect_noext,
  rpmsave = detect_noext,
  rmpnew = detect_noext,
  -- END EXTENSION
}

--- @type vim.filetype.mapping
local filename = {
  -- BEGIN FILENAME
  ['a2psrc'] = 'a2ps',
  ['/etc/a2ps.cfg'] = 'a2ps',
  ['.a2psrc'] = 'a2ps',
  ['.asoundrc'] = 'alsaconf',
  ['/usr/share/alsa/alsa.conf'] = 'alsaconf',
  ['/etc/asound.conf'] = 'alsaconf',
  ['build.xml'] = 'ant',
  ['.htaccess'] = 'apache',
  ['apt.conf'] = 'aptconf',
  ['/.aptitude/config'] = 'aptconf',
  ['=tagging-method'] = 'arch',
  ['.arch-inventory'] = 'arch',
  ['GNUmakefile.am'] = 'automake',
  ['named.root'] = 'bindzone',
  WORKSPACE = 'bzl',
  ['WORKSPACE.bzlmod'] = 'bzl',
  BUCK = 'bzl',
  BUILD = 'bzl',
  ['cabal.project'] = 'cabalproject',
  ['cabal.config'] = 'cabalconfig',
  calendar = 'calendar',
  catalog = 'catalog',
  ['/etc/cdrdao.conf'] = 'cdrdaoconf',
  ['.cdrdao'] = 'cdrdaoconf',
  ['/etc/default/cdrdao'] = 'cdrdaoconf',
  ['/etc/defaults/cdrdao'] = 'cdrdaoconf',
  ['cfengine.conf'] = 'cfengine',
  cgdbrc = 'cgdbrc',
  ['init.trans'] = 'clojure',
  ['.trans'] = 'clojure',
  ['CMakeLists.txt'] = 'cmake',
  ['CMakeCache.txt'] = 'cmakecache',
  ['.cling_history'] = 'cpp',
  ['.alias'] = detect.csh,
  ['.cshrc'] = detect.csh,
  ['.login'] = detect.csh,
  ['csh.cshrc'] = detect.csh,
  ['csh.login'] = detect.csh,
  ['csh.logout'] = detect.csh,
  ['auto.master'] = 'conf',
  ['texdoc.cnf'] = 'conf',
  ['.x11vncrc'] = 'conf',
  ['.chktexrc'] = 'conf',
  ['.ripgreprc'] = 'conf',
  ripgreprc = 'conf',
  ['.mbsyncrc'] = 'conf',
  ['configure.in'] = 'config',
  ['configure.ac'] = 'config',
  crontab = 'crontab',
  ['.cvsrc'] = 'cvsrc',
  ['/debian/changelog'] = 'debchangelog',
  ['changelog.dch'] = 'debchangelog',
  ['changelog.Debian'] = 'debchangelog',
  ['NEWS.dch'] = 'debchangelog',
  ['NEWS.Debian'] = 'debchangelog',
  ['/debian/control'] = 'debcontrol',
  ['/debian/copyright'] = 'debcopyright',
  ['/etc/apt/sources.list'] = 'debsources',
  ['denyhosts.conf'] = 'denyhosts',
  ['dict.conf'] = 'dictconf',
  ['.dictrc'] = 'dictconf',
  ['/etc/DIR_COLORS'] = 'dircolors',
  ['.dir_colors'] = 'dircolors',
  ['.dircolors'] = 'dircolors',
  ['/etc/dnsmasq.conf'] = 'dnsmasq',
  Containerfile = 'dockerfile',
  dockerfile = 'dockerfile',
  Dockerfile = 'dockerfile',
  npmrc = 'dosini',
  ['/etc/yum.conf'] = 'dosini',
  ['.npmrc'] = 'dosini',
  ['pip.conf'] = 'dosini',
  ['setup.cfg'] = 'dosini',
  ['pudb.cfg'] = 'dosini',
  ['.coveragerc'] = 'dosini',
  ['.pypirc'] = 'dosini',
  ['.pylintrc'] = 'dosini',
  ['pylintrc'] = 'dosini',
  ['.replyrc'] = 'dosini',
  ['.gitlint'] = 'dosini',
  ['.oelint.cfg'] = 'dosini',
  ['psprint.conf'] = 'dosini',
  sofficerc = 'dosini',
  ['mimeapps.list'] = 'dosini',
  ['.wakatime.cfg'] = 'dosini',
  ['nfs.conf'] = 'dosini',
  ['nfsmount.conf'] = 'dosini',
  ['.notmuch-config'] = 'dosini',
  ['pacman.conf'] = 'confini',
  ['paru.conf'] = 'confini',
  ['mpv.conf'] = 'confini',
  dune = 'dune',
  jbuild = 'dune',
  ['dune-workspace'] = 'dune',
  ['dune-project'] = 'dune',
  Earthfile = 'earthfile',
  ['.editorconfig'] = 'editorconfig',
  ['elinks.conf'] = 'elinks',
  ['mix.lock'] = 'elixir',
  ['filter-rules'] = 'elmfilt',
  ['exim.conf'] = 'exim',
  exports = 'exports',
  ['.fetchmailrc'] = 'fetchmail',
  fvSchemes = detect.foam,
  fvSolution = detect.foam,
  fvConstraints = detect.foam,
  fvModels = detect.foam,
  fstab = 'fstab',
  mtab = 'fstab',
  ['.gdbinit'] = 'gdb',
  gdbinit = 'gdb',
  ['.gdbearlyinit'] = 'gdb',
  gdbearlyinit = 'gdb',
  ['lltxxxxx.txt'] = 'gedcom',
  TAG_EDITMSG = 'gitcommit',
  MERGE_MSG = 'gitcommit',
  COMMIT_EDITMSG = 'gitcommit',
  NOTES_EDITMSG = 'gitcommit',
  EDIT_DESCRIPTION = 'gitcommit',
  ['.gitconfig'] = 'gitconfig',
  ['.gitmodules'] = 'gitconfig',
  ['.gitattributes'] = 'gitattributes',
  ['.gitignore'] = 'gitignore',
  ['gitolite.conf'] = 'gitolite',
  ['git-rebase-todo'] = 'gitrebase',
  gkrellmrc = 'gkrellmrc',
  ['.gnashrc'] = 'gnash',
  ['.gnashpluginrc'] = 'gnash',
  gnashpluginrc = 'gnash',
  gnashrc = 'gnash',
  ['.gnuplot_history'] = 'gnuplot',
  ['go.sum'] = 'gosum',
  ['go.work.sum'] = 'gosum',
  ['go.work'] = 'gowork',
  ['.gprc'] = 'gp',
  ['/.gnupg/gpg.conf'] = 'gpg',
  ['/.gnupg/options'] = 'gpg',
  Jenkinsfile = 'groovy',
  ['/var/backups/gshadow.bak'] = 'group',
  ['/etc/gshadow'] = 'group',
  ['/etc/group-'] = 'group',
  ['/etc/gshadow.edit'] = 'group',
  ['/etc/gshadow-'] = 'group',
  ['/etc/group'] = 'group',
  ['/var/backups/group.bak'] = 'group',
  ['/etc/group.edit'] = 'group',
  ['/boot/grub/menu.lst'] = 'grub',
  ['/etc/grub.conf'] = 'grub',
  ['/boot/grub/grub.conf'] = 'grub',
  ['.gtkrc'] = 'gtkrc',
  gtkrc = 'gtkrc',
  ['snort.conf'] = 'hog',
  ['vision.conf'] = 'hog',
  ['/etc/host.conf'] = 'hostconf',
  ['/etc/hosts.allow'] = 'hostsaccess',
  ['/etc/hosts.deny'] = 'hostsaccess',
  ['hyprland.conf'] = 'hyprlang',
  ['hyprpaper.conf'] = 'hyprlang',
  ['hypridle.conf'] = 'hyprlang',
  ['hyprlock.conf'] = 'hyprlang',
  ['/.icewm/menu'] = 'icemenu',
  ['.indent.pro'] = 'indent',
  indentrc = 'indent',
  inittab = 'inittab',
  ['ipf.conf'] = 'ipfilter',
  ['ipf6.conf'] = 'ipfilter',
  ['ipf.rules'] = 'ipfilter',
  ['.node_repl_history'] = 'javascript',
  ['Pipfile.lock'] = 'json',
  ['.firebaserc'] = 'json',
  ['.prettierrc'] = 'json',
  ['.stylelintrc'] = 'json',
  ['.lintstagedrc'] = 'json',
  ['flake.lock'] = 'json',
  ['.babelrc'] = 'jsonc',
  ['.eslintrc'] = 'jsonc',
  ['.hintrc'] = 'jsonc',
  ['.jscsrc'] = 'jsonc',
  ['.jsfmtrc'] = 'jsonc',
  ['.jshintrc'] = 'jsonc',
  ['.luaurc'] = 'jsonc',
  ['.swrc'] = 'jsonc',
  ['.vsconfig'] = 'jsonc',
  ['.justfile'] = 'just',
  Kconfig = 'kconfig',
  ['Kconfig.debug'] = 'kconfig',
  ['Config.in'] = 'kconfig',
  ['ldaprc'] = 'ldapconf',
  ['.ldaprc'] = 'ldapconf',
  ['ldap.conf'] = 'ldapconf',
  ['lftp.conf'] = 'lftp',
  ['.lftprc'] = 'lftp',
  ['/.libao'] = 'libao',
  ['/etc/libao.conf'] = 'libao',
  ['lilo.conf'] = 'lilo',
  ['/etc/limits'] = 'limits',
  ['.emacs'] = 'lisp',
  sbclrc = 'lisp',
  ['.sbclrc'] = 'lisp',
  ['.sawfishrc'] = 'lisp',
  ['/etc/login.access'] = 'loginaccess',
  ['/etc/login.defs'] = 'logindefs',
  ['.lsl'] = detect.lsl,
  ['.busted'] = 'lua',
  ['.luacheckrc'] = 'lua',
  ['.lua_history'] = 'lua',
  ['config.ld'] = 'lua',
  ['rock_manifest'] = 'lua',
  ['lynx.cfg'] = 'lynx',
  ['m3overrides'] = 'm3build',
  ['m3makefile'] = 'm3build',
  ['cm3.cfg'] = 'm3quake',
  ['.m4_history'] = 'm4',
  ['.followup'] = 'mail',
  ['.article'] = 'mail',
  ['.letter'] = 'mail',
  ['/etc/aliases'] = 'mailaliases',
  ['/etc/mail/aliases'] = 'mailaliases',
  mailcap = 'mailcap',
  ['.mailcap'] = 'mailcap',
  Kbuild = 'make',
  ['/etc/man.conf'] = 'manconf',
  ['man.config'] = 'manconf',
  ['maxima-init.mac'] = 'maxima',
  ['meson.build'] = 'meson',
  ['meson.options'] = 'meson',
  ['meson_options.txt'] = 'meson',
  ['/etc/conf.modules'] = 'modconf',
  ['/etc/modules'] = 'modconf',
  ['/etc/modules.conf'] = 'modconf',
  ['/.mplayer/config'] = 'mplayerconf',
  ['mplayer.conf'] = 'mplayerconf',
  mrxvtrc = 'mrxvtrc',
  ['.mrxvtrc'] = 'mrxvtrc',
  ['.msmtprc'] = 'msmtp',
  ['.mysql_history'] = 'mysql',
  ['/etc/nanorc'] = 'nanorc',
  Neomuttrc = 'neomuttrc',
  ['.netrc'] = 'netrc',
  NEWS = detect.news,
  ['.ocamlinit'] = 'ocaml',
  ['.octaverc'] = 'octave',
  octaverc = 'octave',
  ['octave.conf'] = 'octave',
  ['.ondirrc'] = 'ondir',
  opam = 'opam',
  ['pacman.log'] = 'pacmanlog',
  ['/etc/pam.conf'] = 'pamconf',
  ['pam_env.conf'] = 'pamenv',
  ['.pam_environment'] = 'pamenv',
  ['/var/backups/passwd.bak'] = 'passwd',
  ['/var/backups/shadow.bak'] = 'passwd',
  ['/etc/passwd'] = 'passwd',
  ['/etc/passwd-'] = 'passwd',
  ['/etc/shadow.edit'] = 'passwd',
  ['/etc/shadow-'] = 'passwd',
  ['/etc/shadow'] = 'passwd',
  ['/etc/passwd.edit'] = 'passwd',
  ['latexmkrc'] = 'perl',
  ['.latexmkrc'] = 'perl',
  ['pf.conf'] = 'pf',
  ['main.cf'] = 'pfmain',
  ['main.cf.proto'] = 'pfmain',
  pinerc = 'pine',
  ['.pinercex'] = 'pine',
  ['.pinerc'] = 'pine',
  pinercex = 'pine',
  ['/etc/pinforc'] = 'pinfo',
  ['/.pinforc'] = 'pinfo',
  ['.povrayrc'] = 'povini',
  printcap = function(path, bufnr)
    return 'ptcap', function(b)
      vim.b[b].ptcap_type = 'print'
    end
  end,
  termcap = function(path, bufnr)
    return 'ptcap', function(b)
      vim.b[b].ptcap_type = 'term'
    end
  end,
  ['.procmailrc'] = 'procmail',
  ['.procmail'] = 'procmail',
  ['indent.pro'] = detect_seq(detect.proto, 'indent'),
  ['/etc/protocols'] = 'protocols',
  INDEX = detect.psf,
  INFO = detect.psf,
  ['MANIFEST.in'] = 'pymanifest',
  ['.pythonstartup'] = 'python',
  ['.pythonrc'] = 'python',
  ['.python_history'] = 'python',
  ['.jline-jython.history'] = 'python',
  SConstruct = 'python',
  qmldir = 'qmldir',
  ['.Rhistory'] = 'r',
  ['.Rprofile'] = 'r',
  Rprofile = 'r',
  ['Rprofile.site'] = 'r',
  ratpoisonrc = 'ratpoison',
  ['.ratpoisonrc'] = 'ratpoison',
  inputrc = 'readline',
  ['.inputrc'] = 'readline',
  ['.reminders'] = 'remind',
  ['requirements.txt'] = 'requirements',
  ['constraints.txt'] = 'requirements',
  ['requirements.in'] = 'requirements',
  ['resolv.conf'] = 'resolv',
  ['robots.txt'] = 'robots',
  Gemfile = 'ruby',
  Puppetfile = 'ruby',
  ['.irbrc'] = 'ruby',
  irbrc = 'ruby',
  ['.irb_history'] = 'ruby',
  irb_history = 'ruby',
  Vagrantfile = 'ruby',
  ['smb.conf'] = 'samba',
  screenrc = 'screen',
  ['.screenrc'] = 'screen',
  ['/etc/sensors3.conf'] = 'sensors',
  ['/etc/sensors.conf'] = 'sensors',
  ['/etc/services'] = 'services',
  ['/etc/serial.conf'] = 'setserial',
  ['/etc/udev/cdsymlinks.conf'] = 'sh',
  ['.ash_history'] = 'sh',
  ['makepkg.conf'] = 'sh',
  ['.makepkg.conf'] = 'sh',
  ['user-dirs.dirs'] = 'sh',
  ['user-dirs.defaults'] = 'sh',
  ['.xprofile'] = 'sh',
  ['bash.bashrc'] = detect.bash,
  bashrc = detect.bash,
  ['.bashrc'] = detect.bash,
  ['.kshrc'] = detect.ksh,
  ['.profile'] = detect.sh,
  ['/etc/profile'] = detect.sh,
  APKBUILD = detect.bash,
  PKGBUILD = detect.bash,
  ['.tcshrc'] = detect.tcsh,
  ['tcsh.login'] = detect.tcsh,
  ['tcsh.tcshrc'] = detect.tcsh,
  ['/etc/slp.conf'] = 'slpconf',
  ['/etc/slp.reg'] = 'slpreg',
  ['/etc/slp.spi'] = 'slpspi',
  ['.slrnrc'] = 'slrnrc',
  ['sendmail.cf'] = 'sm',
  Snakefile = 'snakemake',
  ['.sqlite_history'] = 'sql',
  ['squid.conf'] = 'squid',
  ['ssh_config'] = 'sshconfig',
  ['sshd_config'] = 'sshdconfig',
  ['/etc/sudoers'] = 'sudoers',
  ['sudoers.tmp'] = 'sudoers',
  ['/etc/sysctl.conf'] = 'sysctl',
  tags = 'tags',
  ['pending.data'] = 'taskdata',
  ['completed.data'] = 'taskdata',
  ['undo.data'] = 'taskdata',
  ['.tclshrc'] = 'tcl',
  ['.wishrc'] = 'tcl',
  ['.tclsh-history'] = 'tcl',
  ['tclsh.rc'] = 'tcl',
  ['.xsctcmdhistory'] = 'tcl',
  ['.xsdbcmdhistory'] = 'tcl',
  ['texmf.cnf'] = 'texmf',
  COPYING = 'text',
  README = detect_seq(detect.haredoc, 'text'),
  LICENSE = 'text',
  AUTHORS = 'text',
  tfrc = 'tf',
  ['.tfrc'] = 'tf',
  ['tidy.conf'] = 'tidy',
  tidyrc = 'tidy',
  ['.tidyrc'] = 'tidy',
  ['.tmux.conf'] = 'tmux',
  ['/.cargo/config'] = 'toml',
  Pipfile = 'toml',
  ['Gopkg.lock'] = 'toml',
  ['/.cargo/credentials'] = 'toml',
  ['Cargo.lock'] = 'toml',
  ['.black'] = 'toml',
  black = detect_line1('tool%.black', 'toml', nil),
  ['trustees.conf'] = 'trustees',
  ['.ts_node_repl_history'] = 'typescript',
  ['/etc/udev/udev.conf'] = 'udevconf',
  ['/etc/updatedb.conf'] = 'updatedb',
  ['fdrupstream.log'] = 'upstreamlog',
  vgrindefs = 'vgrindefs',
  ['.exrc'] = 'vim',
  ['_exrc'] = 'vim',
  ['.netrwhist'] = 'vim',
  ['_viminfo'] = 'viminfo',
  ['.viminfo'] = 'viminfo',
  ['.wgetrc'] = 'wget',
  ['.wget2rc'] = 'wget2',
  wgetrc = 'wget',
  wget2rc = 'wget2',
  ['.wvdialrc'] = 'wvdial',
  ['wvdial.conf'] = 'wvdial',
  ['.XCompose'] = 'xcompose',
  ['Compose'] = 'xcompose',
  ['.Xresources'] = 'xdefaults',
  ['.Xpdefaults'] = 'xdefaults',
  ['xdm-config'] = 'xdefaults',
  ['.Xdefaults'] = 'xdefaults',
  ['xorg.conf'] = detect.xfree86_v4,
  ['xorg.conf-4'] = detect.xfree86_v4,
  ['XF86Config'] = detect.xfree86_v3,
  ['/etc/xinetd.conf'] = 'xinetd',
  fglrxrc = 'xml',
  ['/etc/blkid.tab'] = 'xml',
  ['/etc/blkid.tab.old'] = 'xml',
  ['fonts.conf'] = 'xml',
  ['.clangd'] = 'yaml',
  ['.clang-format'] = 'yaml',
  ['.clang-tidy'] = 'yaml',
  ['yarn.lock'] = 'yaml',
  matplotlibrc = 'yaml',
  zathurarc = 'zathurarc',
  ['/etc/zprofile'] = 'zsh',
  ['.zlogin'] = 'zsh',
  ['.zlogout'] = 'zsh',
  ['.zshrc'] = 'zsh',
  ['.zprofile'] = 'zsh',
  ['.zcompdump'] = 'zsh',
  ['.zsh_history'] = 'zsh',
  ['.zshenv'] = 'zsh',
  ['.zfbfmarks'] = 'zsh',
  -- END FILENAME
}

-- Common fast patterns used to increase performance of matching similar regular patterns
--
-- When assigned in options for regular pattern, fast pattern should:
-- - Match at least the same set of strings as its regular pattern. But not too much more.
-- - Be fast to match (will be matched directly with `string.match(target, fastpat)`).
--
-- It will be matched before regular pattern with the following effect afterwards:
-- - If none of pattern matching candidates matches, then skip regular pattern (expensive) matching.
-- - Otherwise, match regular pattern as if nothing happened.
--
-- The core idea behind speedup is that matching results of fast patterns are cached and reused
-- inside single same `M.match()` call. The effect is as big as the quality of compromise between:
-- - Same fast pattern is present in many regular patterns options: leads to better reusing cache if
--   there is no match.
-- - Fast pattern is specific: leads to less "fast pattern matches but regular one does not" which
--   has the penalty of a (not useful) single extra fast pattern match.
--
-- Example:
-- - Regular pattern: '.*/etc/a2ps/.*%.cfg'.
-- - Good fast patterns: '/etc/'; '%.cfg$' (which is better, depends on how many times each is used)
-- - Bad fast patterns: '%.' (fast but not specific), '/a2ps/.*%.' (slow but specific)
--
-- When adding new filetype with regular pattern matching rule, consider the following:
-- - If there is a fast pattern which can be used for the new regular pattern, use it.
-- - If there can be a fast and specific enough pattern to be added to at least 3 regular patterns,
--   add it to the table below and use it in a way similar to some other already used pattern.
--   Good new fast pattern should be:
--     - Fast. Good rule of thumb is that it should be a short specific string (i.e. no quantifiers
--       or character sets).
--     - Specific. Good rules of thumb (from best to worst):
--         - Full directory name (like '/etc/', '/log/').
--         - Part of a rare enough directory name (like '/conf', 'git/').
--         - Character sequence reasonably rarely used in real full paths (like 'nginx', 'cmus').
--
-- When modifying an existing regular pattern, make sure that its fast pattern remains valid.
local fast_pattern = {
  dir_debian = { fastpat = '/debian/' },
  dir_etc = { fastpat = '/etc/' },
  dir_log = { fastpat = '/log/' },
  dir_systemd = { fastpat = '/systemd/' },
  dir_usr = { fastpat = '/usr/' },
  dir_var = { fastpat = '/var/' },
  dirend_calendar = { fastpat = 'calendar/' },
  dirend_git = { fastpat = 'git/' },
  dirstart_conf = { fastpat = '/conf' },
  dirstart_dot = { fastpat = '/%.' },
  plain_bash = { fastpat = 'bash' },
  plain_cmus = { fastpat = 'cmus' },
  plain_dotcfg = { fastpat = '%.cfg' },
  plain_dotconf = { fastpat = '%.conf' },
  plain_dotmeta = { fastpat = '%.meta' },
  plain_file = { fastpat = 'file' },
  plain_fvwm = { fastpat = 'fvwm' },
  plain_nginx = { fastpat = 'nginx' },
  plain_projdotuser = { fastpat = 'proj%.user' },
  plain_require = { fastpat = 'require' },
  plain_s6 = { fastpat = 's6' },
  plain_utt = { fastpat = 'utt' },
  start_dot = { fastpat = '^%.' },
}

-- Re-use closures as much as possible
local detect_apache_dir_etc = starsetf('apache', fast_pattern.dir_etc)
local detect_apache_plain_dotconf = starsetf('apache', fast_pattern.plain_dotconf)
local detect_muttrc = starsetf('muttrc', fast_pattern.plain_utt)
local detect_neomuttrc = starsetf('neomuttrc', fast_pattern.plain_utt)

local messages_dir_log = { 'messages', fast_pattern.dir_log }
local systemd_dir_systemd = { 'systemd', fast_pattern.dir_systemd }

--- @type vim.filetype.mapping
local pattern = {
  -- BEGIN PATTERN
  ['.*/etc/a2ps/.*%.cfg'] = { 'a2ps', fast_pattern.dir_etc },
  ['.*/etc/a2ps%.cfg'] = { 'a2ps', fast_pattern.dir_etc },
  ['.*/usr/share/alsa/alsa%.conf'] = { 'alsaconf', fast_pattern.dir_usr },
  ['.*/etc/asound%.conf'] = { 'alsaconf', fast_pattern.dir_etc },
  ['.*/etc/apache2/sites%-.*/.*%.com'] = { 'apache', fast_pattern.dir_etc },
  ['.*/etc/httpd/.*%.conf'] = { 'apache', fast_pattern.dir_etc },
  ['.*/etc/apache2/.*%.conf.*'] = detect_apache_dir_etc,
  ['.*/etc/apache2/conf%..*/.*'] = detect_apache_dir_etc,
  ['.*/etc/apache2/mods%-.*/.*'] = detect_apache_dir_etc,
  ['.*/etc/apache2/sites%-.*/.*'] = detect_apache_dir_etc,
  ['access%.conf.*'] = detect_apache_plain_dotconf,
  ['apache%.conf.*'] = detect_apache_plain_dotconf,
  ['apache2%.conf.*'] = detect_apache_plain_dotconf,
  ['httpd%.conf.*'] = detect_apache_plain_dotconf,
  ['srm%.conf.*'] = detect_apache_plain_dotconf,
  ['.*/etc/httpd/conf%..*/.*'] = detect_apache_dir_etc,
  ['.*/etc/httpd/conf%.d/.*%.conf.*'] = detect_apache_dir_etc,
  ['.*/etc/httpd/mods%-.*/.*'] = detect_apache_dir_etc,
  ['.*/etc/httpd/sites%-.*/.*'] = detect_apache_dir_etc,
  ['.*/etc/proftpd/.*%.conf.*'] = starsetf('apachestyle', fast_pattern.dir_etc),
  ['.*/etc/proftpd/conf%..*/.*'] = starsetf('apachestyle', fast_pattern.dir_etc),
  ['proftpd%.conf.*'] = starsetf('apachestyle', fast_pattern.plain_dotconf),
  ['.*asterisk/.*%.conf.*'] = starsetf('asterisk', fast_pattern.plain_dotconf),
  ['.*asterisk.*/.*voicemail%.conf.*'] = starsetf('asteriskvm', fast_pattern.plain_dotconf),
  ['.*/%.aptitude/config'] = { 'aptconf', fast_pattern.dirstart_conf },
  ['[mM]akefile%.am'] = { 'automake', fast_pattern.plain_file },
  ['.*/bind/db%..*'] = starsetf('bindzone'),
  ['.*/named/db%..*'] = starsetf('bindzone'),
  ['.*/build/conf/.*%.conf'] = { 'bitbake', fast_pattern.dirstart_conf },
  ['.*/meta/conf/.*%.conf'] = { 'bitbake', fast_pattern.dirstart_conf },
  ['.*/meta%-.*/conf/.*%.conf'] = { 'bitbake', fast_pattern.dirstart_conf },
  ['.*%.blade%.php'] = 'blade',
  ['bzr_log%..*'] = 'bzr',
  ['.*enlightenment/.*%.cfg'] = { 'c', fast_pattern.plain_dotcfg },
  ['.*/%.cabal/config'] = { 'cabalconfig', fast_pattern.dirstart_conf },
  ['.*/cabal/config'] = { 'cabalconfig', fast_pattern.dirstart_conf },
  ['cabal%.project%..*'] = starsetf('cabalproject'),
  ['.*/%.calendar/.*'] = starsetf('calendar', fast_pattern.dirend_calendar),
  ['.*/share/calendar/.*/calendar%..*'] = starsetf('calendar', fast_pattern.dirend_calendar),
  ['.*/share/calendar/calendar%..*'] = starsetf('calendar', fast_pattern.dirend_calendar),
  ['sgml%.catalog.*'] = starsetf('catalog'),
  ['.*/etc/defaults/cdrdao'] = { 'cdrdaoconf', fast_pattern.dir_etc },
  ['.*/etc/cdrdao%.conf'] = { 'cdrdaoconf', fast_pattern.dir_etc },
  ['.*/etc/default/cdrdao'] = { 'cdrdaoconf', fast_pattern.dir_etc },
  ['.*hgrc'] = 'cfg',
  ['.*%.[Cc][Ff][Gg]'] = {
    detect.cfg,
    -- Decrease priority to avoid conflicts with more specific patterns
    -- such as '.*/etc/a2ps/.*%.cfg', '.*enlightenment/.*%.cfg', etc.
    { priority = -1 },
  },
  ['[cC]hange[lL]og.*'] = starsetf(detect.changelog),
  ['.*%.%.ch'] = 'chill',
  ['.*/etc/translate%-shell'] = { 'clojure', fast_pattern.dir_etc },
  ['.*%.cmake%.in'] = 'cmake',
  -- */cmus/rc and */.cmus/rc
  ['.*/%.?cmus/rc'] = { 'cmusrc', fast_pattern.plain_cmus },
  -- */cmus/*.theme and */.cmus/*.theme
  ['.*/%.?cmus/.*%.theme'] = { 'cmusrc', fast_pattern.plain_cmus },
  ['.*/%.cmus/autosave'] = { 'cmusrc', fast_pattern.plain_cmus },
  ['.*/%.cmus/command%-history'] = { 'cmusrc', fast_pattern.plain_cmus },
  ['.*/etc/hostname%..*'] = starsetf('config', fast_pattern.dir_etc),
  ['crontab%..*'] = starsetf('crontab'),
  ['.*/etc/cron%.d/.*'] = starsetf('crontab', fast_pattern.dir_etc),
  ['%.cshrc.*'] = { detect.csh, fast_pattern.start_dot },
  ['%.login.*'] = { detect.csh, fast_pattern.start_dot },
  ['cvs%d+'] = 'cvs',
  ['.*%.[Dd][Aa][Tt]'] = detect.dat,
  ['.*/debian/patches/.*'] = { detect.dep3patch, fast_pattern.dir_debian },
  ['.*/etc/dnsmasq%.d/.*'] = starsetf('dnsmasq', fast_pattern.dir_etc),
  ['Containerfile%..*'] = starsetf('dockerfile', fast_pattern.plain_file),
  ['Dockerfile%..*'] = starsetf('dockerfile', fast_pattern.plain_file),
  ['.*/etc/yum%.repos%.d/.*'] = starsetf('dosini', fast_pattern.dir_etc),
  ['drac%..*'] = starsetf('dracula'),
  ['.*/debian/changelog'] = { 'debchangelog', fast_pattern.dir_debian },
  ['.*/debian/control'] = { 'debcontrol', fast_pattern.dir_debian },
  ['.*/debian/copyright'] = { 'debcopyright', fast_pattern.dir_debian },
  ['.*/etc/apt/sources%.list%.d/.*%.list'] = { 'debsources', fast_pattern.dir_etc },
  ['.*/etc/apt/sources%.list'] = { 'debsources', fast_pattern.dir_etc },
  ['.*/etc/apt/sources%.list%.d/.*%.sources'] = { 'deb822sources', fast_pattern.dir_etc },
  ['dictd.*%.conf'] = { 'dictdconf', fast_pattern.plain_dotconf },
  ['.*/etc/DIR_COLORS'] = { 'dircolors', fast_pattern.dir_etc },
  ['.*/etc/dnsmasq%.conf'] = { 'dnsmasq', fast_pattern.dir_etc },
  ['php%.ini%-.*'] = 'dosini',
  ['.*/%.aws/config'] = { 'confini', fast_pattern.dirstart_conf },
  ['.*/%.aws/credentials'] = { 'confini', fast_pattern.dirstart_dot },
  ['.*/etc/yum%.conf'] = { 'dosini', fast_pattern.dir_etc },
  ['.*/lxqt/.*%.conf'] = { 'dosini', fast_pattern.plain_dotconf },
  ['.*/screengrab/.*%.conf'] = { 'dosini', fast_pattern.plain_dotconf },
  ['.*/bpython/config'] = { 'dosini', fast_pattern.dirstart_conf },
  ['.*/mypy/config'] = { 'dosini', fast_pattern.dirstart_conf },
  ['.*/flatpak/repo/config'] = { 'dosini', fast_pattern.dirstart_conf },
  ['.*lvs'] = 'dracula',
  ['.*lpe'] = 'dracula',
  ['.*/dtrace/.*%.d'] = 'dtrace',
  ['.*esmtprc'] = 'esmtprc',
  ['.*Eterm/.*%.cfg'] = { 'eterm', fast_pattern.plain_dotcfg },
  ['.*s6.*/up'] = { 'execline', fast_pattern.plain_s6 },
  ['.*s6.*/down'] = { 'execline', fast_pattern.plain_s6 },
  ['.*s6.*/run'] = { 'execline', fast_pattern.plain_s6 },
  ['.*s6.*/finish'] = { 'execline', fast_pattern.plain_s6 },
  ['s6%-.*'] = { 'execline', fast_pattern.plain_s6 },
  ['[a-zA-Z0-9].*Dict'] = detect.foam,
  ['[a-zA-Z0-9].*Dict%..*'] = detect.foam,
  ['[a-zA-Z].*Properties'] = detect.foam,
  ['[a-zA-Z].*Properties%..*'] = detect.foam,
  ['.*Transport%..*'] = detect.foam,
  ['.*/constant/g'] = detect.foam,
  ['.*/0/.*'] = detect.foam,
  ['.*/0%.orig/.*'] = detect.foam,
  ['.*/%.fvwm/.*'] = starsetf('fvwm', fast_pattern.plain_fvwm),
  ['.*fvwmrc.*'] = starsetf(detect.fvwm_v1, fast_pattern.plain_fvwm),
  ['.*fvwm95.*%.hook'] = starsetf(detect.fvwm_v1, fast_pattern.plain_fvwm),
  ['.*fvwm2rc.*'] = starsetf(detect.fvwm_v2, fast_pattern.plain_fvwm),
  ['.*/tmp/lltmp.*'] = starsetf('gedcom'),
  ['.*/etc/gitconfig%.d/.*'] = starsetf('gitconfig', fast_pattern.dir_etc),
  ['.*/gitolite%-admin/conf/.*'] = starsetf('gitolite', fast_pattern.dirstart_conf),
  ['tmac%..*'] = starsetf('nroff'),
  ['.*/%.gitconfig%.d/.*'] = starsetf('gitconfig', fast_pattern.dirstart_dot),
  ['.*%.git/.*'] = {
    detect.git,
    -- Decrease priority to run after simple pattern checks
    { fastpat = fast_pattern.dirend_git.fastpat, priority = -1 },
  },
  ['.*%.git/modules/.*/config'] = { 'gitconfig', fast_pattern.dirstart_conf },
  ['.*%.git/modules/config'] = { 'gitconfig', fast_pattern.dirstart_conf },
  ['.*%.git/config'] = { 'gitconfig', fast_pattern.dirstart_conf },
  ['.*/etc/gitconfig'] = { 'gitconfig', fast_pattern.dir_etc },
  ['.*/%.config/git/config'] = { 'gitconfig', fast_pattern.dirstart_conf },
  ['.*%.git/config%.worktree'] = { 'gitconfig', fast_pattern.dirstart_conf },
  ['.*%.git/worktrees/.*/config%.worktree'] = { 'gitconfig', fast_pattern.dirstart_conf },
  ['${XDG_CONFIG_HOME}/git/config'] = { 'gitconfig', fast_pattern.dirstart_conf },
  ['.*%.git/info/attributes'] = { 'gitattributes', fast_pattern.dirend_git },
  ['.*/etc/gitattributes'] = { 'gitattributes', fast_pattern.dir_etc },
  ['.*/%.config/git/attributes'] = { 'gitattributes', fast_pattern.dirend_git },
  ['${XDG_CONFIG_HOME}/git/attributes'] = { 'gitattributes', fast_pattern.dirend_git },
  ['.*%.git/info/exclude'] = { 'gitignore', fast_pattern.dirend_git },
  ['.*/%.config/git/ignore'] = { 'gitignore', fast_pattern.dirend_git },
  ['${XDG_CONFIG_HOME}/git/ignore'] = { 'gitignore', fast_pattern.dirend_git },
  ['%.gitsendemail%.msg%.......'] = { 'gitsendemail', fast_pattern.start_dot },
  ['gkrellmrc_.'] = 'gkrellmrc',
  ['.*/usr/.*/gnupg/options%.skel'] = { 'gpg', fast_pattern.dir_usr },
  ['.*/%.gnupg/options'] = { 'gpg', fast_pattern.dirstart_dot },
  ['.*/%.gnupg/gpg%.conf'] = { 'gpg', fast_pattern.dirstart_dot },
  ['${GNUPGHOME}/options'] = 'gpg',
  ['${GNUPGHOME}/gpg%.conf'] = 'gpg',
  ['.*/etc/group'] = { 'group', fast_pattern.dir_etc },
  ['.*/etc/gshadow'] = { 'group', fast_pattern.dir_etc },
  ['.*/etc/group%.edit'] = { 'group', fast_pattern.dir_etc },
  ['.*/var/backups/gshadow%.bak'] = { 'group', fast_pattern.dir_var },
  ['.*/etc/group%-'] = { 'group', fast_pattern.dir_etc },
  ['.*/etc/gshadow%-'] = { 'group', fast_pattern.dir_etc },
  ['.*/var/backups/group%.bak'] = { 'group', fast_pattern.dir_var },
  ['.*/etc/gshadow%.edit'] = { 'group', fast_pattern.dir_etc },
  ['.*/boot/grub/grub%.conf'] = { 'grub', fast_pattern.plain_dotconf },
  ['.*/boot/grub/menu%.lst'] = 'grub',
  ['.*/etc/grub%.conf'] = { 'grub', fast_pattern.dir_etc },
  -- gtkrc* and .gtkrc*
  ['%.?gtkrc.*'] = starsetf('gtkrc'),
  ['${VIMRUNTIME}/doc/.*%.txt'] = 'help',
  ['hg%-editor%-.*%.txt'] = 'hgcommit',
  ['.*/etc/host%.conf'] = { 'hostconf', fast_pattern.dir_etc },
  ['.*/etc/hosts%.deny'] = { 'hostsaccess', fast_pattern.dir_etc },
  ['.*/etc/hosts%.allow'] = { 'hostsaccess', fast_pattern.dir_etc },
  ['.*%.html%.m4'] = 'htmlm4',
  ['.*/%.i3/config'] = { 'i3config', fast_pattern.dirstart_conf },
  ['.*/i3/config'] = { 'i3config', fast_pattern.dirstart_conf },
  ['.*/%.icewm/menu'] = { 'icemenu', fast_pattern.dirstart_dot },
  ['.*/etc/initng/.*/.*%.i'] = { 'initng', fast_pattern.dir_etc },
  ['JAM.*%..*'] = starsetf('jam'),
  ['Prl.*%..*'] = starsetf('jam'),
  ['.*%.properties_..'] = 'jproperties',
  ['.*%.properties_.._..'] = 'jproperties',
  ['org%.eclipse%..*%.prefs'] = 'jproperties',
  ['.*%.properties_.._.._.*'] = starsetf('jproperties'),
  ['[jt]sconfig.*%.json'] = 'jsonc',
  ['[jJ]ustfile'] = { 'just', fast_pattern.plain_file },
  ['Kconfig%..*'] = starsetf('kconfig'),
  ['Config%.in%..*'] = starsetf('kconfig'),
  ['.*%.[Ss][Uu][Bb]'] = 'krl',
  ['lilo%.conf.*'] = starsetf('lilo', fast_pattern.plain_dotconf),
  ['.*/etc/logcheck/.*%.d.*/.*'] = starsetf('logcheck', fast_pattern.dir_etc),
  ['.*/ldscripts/.*'] = 'ld',
  ['.*lftp/rc'] = 'lftp',
  ['.*/%.libao'] = { 'libao', fast_pattern.dirstart_dot },
  ['.*/etc/libao%.conf'] = { 'libao', fast_pattern.dir_etc },
  ['.*/etc/.*limits%.conf'] = { 'limits', fast_pattern.dir_etc },
  ['.*/etc/limits'] = { 'limits', fast_pattern.dir_etc },
  ['.*/etc/.*limits%.d/.*%.conf'] = { 'limits', fast_pattern.dir_etc },
  ['.*/supertux2/config'] = { 'lisp', fast_pattern.dirstart_conf },
  ['.*/LiteStep/.*/.*%.rc'] = 'litestep',
  ['.*/etc/login%.access'] = { 'loginaccess', fast_pattern.dir_etc },
  ['.*/etc/login%.defs'] = { 'logindefs', fast_pattern.dir_etc },
  ['%.letter%.%d+'] = { 'mail', fast_pattern.start_dot },
  ['%.article%.%d+'] = { 'mail', fast_pattern.start_dot },
  ['/tmp/SLRN[0-9A-Z.]+'] = 'mail',
  ['ae%d+%.txt'] = 'mail',
  ['pico%.%d+'] = 'mail',
  ['mutt%-.*%-%w+'] = { 'mail', fast_pattern.plain_utt },
  ['muttng%-.*%-%w+'] = { 'mail', fast_pattern.plain_utt },
  ['neomutt%-.*%-%w+'] = { 'mail', fast_pattern.plain_utt },
  ['mutt' .. string.rep('[%w_-]', 6)] = { 'mail', fast_pattern.plain_utt },
  ['neomutt' .. string.rep('[%w_-]', 6)] = { 'mail', fast_pattern.plain_utt },
  ['snd%.%d+'] = 'mail',
  ['reportbug%-.*'] = starsetf('mail'),
  ['.*/etc/mail/aliases'] = { 'mailaliases', fast_pattern.dir_etc },
  ['.*/etc/aliases'] = { 'mailaliases', fast_pattern.dir_etc },
  ['.*[mM]akefile'] = { 'make', fast_pattern.plain_file },
  ['[mM]akefile.*'] = starsetf('make', fast_pattern.plain_file),
  ['.*/etc/man%.conf'] = { 'manconf', fast_pattern.dir_etc },
  ['.*/log/auth'] = messages_dir_log,
  ['.*/log/cron'] = messages_dir_log,
  ['.*/log/daemon'] = messages_dir_log,
  ['.*/log/debug'] = messages_dir_log,
  ['.*/log/kern'] = messages_dir_log,
  ['.*/log/lpr'] = messages_dir_log,
  ['.*/log/mail'] = messages_dir_log,
  ['.*/log/messages'] = messages_dir_log,
  ['.*/log/news/news'] = messages_dir_log,
  ['.*/log/syslog'] = messages_dir_log,
  ['.*/log/user'] = messages_dir_log,
  ['.*/log/auth%.log'] = messages_dir_log,
  ['.*/log/cron%.log'] = messages_dir_log,
  ['.*/log/daemon%.log'] = messages_dir_log,
  ['.*/log/debug%.log'] = messages_dir_log,
  ['.*/log/kern%.log'] = messages_dir_log,
  ['.*/log/lpr%.log'] = messages_dir_log,
  ['.*/log/mail%.log'] = messages_dir_log,
  ['.*/log/messages%.log'] = messages_dir_log,
  ['.*/log/news/news%.log'] = messages_dir_log,
  ['.*/log/syslog%.log'] = messages_dir_log,
  ['.*/log/user%.log'] = messages_dir_log,
  ['.*/log/auth%.err'] = messages_dir_log,
  ['.*/log/cron%.err'] = messages_dir_log,
  ['.*/log/daemon%.err'] = messages_dir_log,
  ['.*/log/debug%.err'] = messages_dir_log,
  ['.*/log/kern%.err'] = messages_dir_log,
  ['.*/log/lpr%.err'] = messages_dir_log,
  ['.*/log/mail%.err'] = messages_dir_log,
  ['.*/log/messages%.err'] = messages_dir_log,
  ['.*/log/news/news%.err'] = messages_dir_log,
  ['.*/log/syslog%.err'] = messages_dir_log,
  ['.*/log/user%.err'] = messages_dir_log,
  ['.*/log/auth%.info'] = messages_dir_log,
  ['.*/log/cron%.info'] = messages_dir_log,
  ['.*/log/daemon%.info'] = messages_dir_log,
  ['.*/log/debug%.info'] = messages_dir_log,
  ['.*/log/kern%.info'] = messages_dir_log,
  ['.*/log/lpr%.info'] = messages_dir_log,
  ['.*/log/mail%.info'] = messages_dir_log,
  ['.*/log/messages%.info'] = messages_dir_log,
  ['.*/log/news/news%.info'] = messages_dir_log,
  ['.*/log/syslog%.info'] = messages_dir_log,
  ['.*/log/user%.info'] = messages_dir_log,
  ['.*/log/auth%.warn'] = messages_dir_log,
  ['.*/log/cron%.warn'] = messages_dir_log,
  ['.*/log/daemon%.warn'] = messages_dir_log,
  ['.*/log/debug%.warn'] = messages_dir_log,
  ['.*/log/kern%.warn'] = messages_dir_log,
  ['.*/log/lpr%.warn'] = messages_dir_log,
  ['.*/log/mail%.warn'] = messages_dir_log,
  ['.*/log/messages%.warn'] = messages_dir_log,
  ['.*/log/news/news%.warn'] = messages_dir_log,
  ['.*/log/syslog%.warn'] = messages_dir_log,
  ['.*/log/user%.warn'] = messages_dir_log,
  ['.*/log/auth%.crit'] = messages_dir_log,
  ['.*/log/cron%.crit'] = messages_dir_log,
  ['.*/log/daemon%.crit'] = messages_dir_log,
  ['.*/log/debug%.crit'] = messages_dir_log,
  ['.*/log/kern%.crit'] = messages_dir_log,
  ['.*/log/lpr%.crit'] = messages_dir_log,
  ['.*/log/mail%.crit'] = messages_dir_log,
  ['.*/log/messages%.crit'] = messages_dir_log,
  ['.*/log/news/news%.crit'] = messages_dir_log,
  ['.*/log/syslog%.crit'] = messages_dir_log,
  ['.*/log/user%.crit'] = messages_dir_log,
  ['.*/log/auth%.notice'] = messages_dir_log,
  ['.*/log/cron%.notice'] = messages_dir_log,
  ['.*/log/daemon%.notice'] = messages_dir_log,
  ['.*/log/debug%.notice'] = messages_dir_log,
  ['.*/log/kern%.notice'] = messages_dir_log,
  ['.*/log/lpr%.notice'] = messages_dir_log,
  ['.*/log/mail%.notice'] = messages_dir_log,
  ['.*/log/messages%.notice'] = messages_dir_log,
  ['.*/log/news/news%.notice'] = messages_dir_log,
  ['.*/log/syslog%.notice'] = messages_dir_log,
  ['.*/log/user%.notice'] = messages_dir_log,
  ['.*%.[Mm][Oo][Dd]'] = detect.mod,
  ['.*/etc/modules%.conf'] = { 'modconf', fast_pattern.dir_etc },
  ['.*/etc/conf%.modules'] = { 'modconf', fast_pattern.dir_etc },
  ['.*/etc/modules'] = { 'modconf', fast_pattern.dir_etc },
  ['.*/etc/modprobe%..*'] = starsetf('modconf', fast_pattern.dir_etc),
  ['.*/etc/modutils/.*'] = starsetf(function(path, bufnr)
    if fn.executable(fn.expand(path)) ~= 1 then
      return 'modconf'
    end
  end, fast_pattern.dir_etc),
  ['Muttrc'] = { 'muttrc', fast_pattern.plain_utt },
  ['Muttngrc'] = { 'muttrc', fast_pattern.plain_utt },
  ['.*/etc/Muttrc%.d/.*'] = starsetf('muttrc', fast_pattern.dir_etc),
  ['.*/%.mplayer/config'] = { 'mplayerconf', fast_pattern.dirstart_conf },
  ['Muttrc.*'] = detect_muttrc,
  ['Muttngrc.*'] = detect_muttrc,
  -- muttrc* and .muttrc*
  ['%.?muttrc.*'] = detect_muttrc,
  -- muttngrc* and .muttngrc*
  ['%.?muttngrc.*'] = detect_muttrc,
  ['.*/%.mutt/muttrc.*'] = detect_muttrc,
  ['.*/%.muttng/muttrc.*'] = detect_muttrc,
  ['.*/%.muttng/muttngrc.*'] = detect_muttrc,
  ['rndc.*%.conf'] = { 'named', fast_pattern.plain_dotconf },
  ['rndc.*%.key'] = 'named',
  ['named.*%.conf'] = { 'named', fast_pattern.plain_dotconf },
  ['.*/etc/nanorc'] = { 'nanorc', fast_pattern.dir_etc },
  ['.*%.NS[ACGLMNPS]'] = 'natural',
  ['Neomuttrc.*'] = detect_neomuttrc,
  -- neomuttrc* and .neomuttrc*
  ['%.?neomuttrc.*'] = detect_neomuttrc,
  ['.*/%.neomutt/neomuttrc.*'] = detect_neomuttrc,
  ['nginx.*%.conf'] = { 'nginx', fast_pattern.plain_nginx },
  ['.*/etc/nginx/.*'] = { 'nginx', fast_pattern.plain_nginx },
  ['.*nginx%.conf'] = { 'nginx', fast_pattern.plain_nginx },
  ['.*/nginx/.*%.conf'] = { 'nginx', fast_pattern.plain_nginx },
  ['.*/usr/local/nginx/conf/.*'] = { 'nginx', fast_pattern.plain_nginx },
  ['.*%.[1-9]'] = detect.nroff,
  ['.*%.ml%.cppo'] = 'ocaml',
  ['.*%.mli%.cppo'] = 'ocaml',
  ['.*/octave/history'] = 'octave',
  ['.*%.opam%.template'] = 'opam',
  ['.*/openvpn/.*/.*%.conf'] = { 'openvpn', fast_pattern.plain_dotconf },
  ['.*%.[Oo][Pp][Ll]'] = 'opl',
  ['.*/etc/pam%.conf'] = { 'pamconf', fast_pattern.dir_etc },
  ['.*/etc/pam%.d/.*'] = starsetf('pamconf', fast_pattern.dir_etc),
  ['.*/etc/passwd%-'] = { 'passwd', fast_pattern.dir_etc },
  ['.*/etc/shadow'] = { 'passwd', fast_pattern.dir_etc },
  ['.*/etc/shadow%.edit'] = { 'passwd', fast_pattern.dir_etc },
  ['.*/var/backups/shadow%.bak'] = { 'passwd', fast_pattern.dir_var },
  ['.*/var/backups/passwd%.bak'] = { 'passwd', fast_pattern.dir_var },
  ['.*/etc/passwd'] = { 'passwd', fast_pattern.dir_etc },
  ['.*/etc/passwd%.edit'] = { 'passwd', fast_pattern.dir_etc },
  ['.*/etc/shadow%-'] = { 'passwd', fast_pattern.dir_etc },
  ['%.?gitolite%.rc'] = { 'perl' },
  ['example%.gitolite%.rc'] = 'perl',
  ['.*%.php%d'] = 'php',
  ['.*/%.pinforc'] = { 'pinfo', fast_pattern.dirstart_dot },
  ['.*/etc/pinforc'] = { 'pinfo', fast_pattern.dir_etc },
  ['.*%.[Pp][Rr][Gg]'] = detect.prg,
  ['.*/etc/protocols'] = { 'protocols', fast_pattern.dir_etc },
  ['.*printcap.*'] = starsetf(function(path, bufnr)
    return require('vim.filetype.detect').printcap('print')
  end),
  ['.*baseq[2-3]/.*%.cfg'] = { 'quake', fast_pattern.plain_dotcfg },
  ['.*quake[1-3]/.*%.cfg'] = { 'quake', fast_pattern.plain_dotcfg },
  ['.*id1/.*%.cfg'] = { 'quake', fast_pattern.plain_dotcfg },
  ['.*/queries/.*%.scm'] = 'query', -- treesitter queries (Neovim only)
  ['.*,v'] = 'rcs',
  ['%.reminders.*'] = starsetf('remind', fast_pattern.start_dot),
  ['.*%-requirements%.txt'] = { 'requirements', fast_pattern.plain_require },
  ['requirements/.*%.txt'] = { 'requirements', fast_pattern.plain_require },
  ['requires/.*%.txt'] = { 'requirements', fast_pattern.plain_require },
  ['[rR]akefile.*'] = starsetf('ruby', fast_pattern.plain_file),
  ['[rR]antfile'] = { 'ruby', fast_pattern.plain_file },
  ['[rR]akefile'] = { 'ruby', fast_pattern.plain_file },
  ['.*/etc/sensors%.d/[^.].*'] = starsetf('sensors', fast_pattern.dir_etc),
  ['.*/etc/sensors%.conf'] = { 'sensors', fast_pattern.dir_etc },
  ['.*/etc/sensors3%.conf'] = { 'sensors', fast_pattern.dir_etc },
  ['.*/etc/services'] = { 'services', fast_pattern.dir_etc },
  ['.*/etc/serial%.conf'] = { 'setserial', fast_pattern.dir_etc },
  ['.*/etc/udev/cdsymlinks%.conf'] = { 'sh', fast_pattern.dir_etc },
  ['.*/neofetch/config%.conf'] = { 'sh', fast_pattern.dirstart_conf },
  ['%.bash[_%-]aliases'] = { detect.bash, fast_pattern.plain_bash },
  ['%.bash[_%-]history'] = { detect.bash, fast_pattern.plain_bash },
  ['%.bash[_%-]logout'] = { detect.bash, fast_pattern.plain_bash },
  ['%.bash[_%-]profile'] = { detect.bash, fast_pattern.plain_bash },
  ['%.kshrc.*'] = { detect.ksh, fast_pattern.start_dot },
  ['%.profile.*'] = { detect.sh, fast_pattern.plain_file },
  ['.*/etc/profile'] = { detect.sh, fast_pattern.dir_etc },
  ['bash%-fc[%-%.].*'] = { detect.bash, fast_pattern.plain_bash },
  ['%.tcshrc.*'] = { detect.tcsh, fast_pattern.start_dot },
  ['.*/etc/sudoers%.d/.*'] = starsetf('sudoers', fast_pattern.dir_etc),
  ['.*%._sst%.meta'] = { 'sisu', fast_pattern.plain_dotmeta },
  ['.*%.%-sst%.meta'] = { 'sisu', fast_pattern.plain_dotmeta },
  ['.*%.sst%.meta'] = { 'sisu', fast_pattern.plain_dotmeta },
  ['.*/etc/slp%.conf'] = { 'slpconf', fast_pattern.dir_etc },
  ['.*/etc/slp%.reg'] = { 'slpreg', fast_pattern.dir_etc },
  ['.*/etc/slp%.spi'] = { 'slpspi', fast_pattern.dir_etc },
  ['.*/etc/ssh/ssh_config%.d/.*%.conf'] = { 'sshconfig', fast_pattern.dir_etc },
  ['.*/%.ssh/config'] = { 'sshconfig', fast_pattern.dirstart_conf },
  ['.*/%.ssh/.*%.conf'] = { 'sshconfig', fast_pattern.plain_dotconf },
  ['.*/etc/ssh/sshd_config%.d/.*%.conf'] = { 'sshdconfig', fast_pattern.dir_etc },
  ['.*%.[Ss][Rr][Cc]'] = detect.src,
  ['.*/etc/sudoers'] = { 'sudoers', fast_pattern.dir_etc },
  ['svn%-commit.*%.tmp'] = 'svn',
  ['.*/sway/config'] = { 'swayconfig', fast_pattern.dirstart_conf },
  ['.*/%.sway/config'] = { 'swayconfig', fast_pattern.dirstart_conf },
  ['.*%.swift%.gyb'] = 'swiftgyb',
  ['.*%.[Ss][Yy][Ss]'] = detect.sys,
  ['.*/etc/sysctl%.conf'] = { 'sysctl', fast_pattern.dir_etc },
  ['.*/etc/sysctl%.d/.*%.conf'] = { 'sysctl', fast_pattern.dir_etc },
  ['.*/systemd/.*%.automount'] = systemd_dir_systemd,
  ['.*/systemd/.*%.dnssd'] = systemd_dir_systemd,
  ['.*/systemd/.*%.link'] = systemd_dir_systemd,
  ['.*/systemd/.*%.mount'] = systemd_dir_systemd,
  ['.*/systemd/.*%.netdev'] = systemd_dir_systemd,
  ['.*/systemd/.*%.network'] = systemd_dir_systemd,
  ['.*/systemd/.*%.nspawn'] = systemd_dir_systemd,
  ['.*/systemd/.*%.path'] = systemd_dir_systemd,
  ['.*/systemd/.*%.service'] = systemd_dir_systemd,
  ['.*/systemd/.*%.slice'] = systemd_dir_systemd,
  ['.*/systemd/.*%.socket'] = systemd_dir_systemd,
  ['.*/systemd/.*%.swap'] = systemd_dir_systemd,
  ['.*/systemd/.*%.target'] = systemd_dir_systemd,
  ['.*/systemd/.*%.timer'] = systemd_dir_systemd,
  ['.*/etc/systemd/.*%.conf%.d/.*%.conf'] = systemd_dir_systemd,
  ['.*/%.config/systemd/user/.*%.d/.*%.conf'] = systemd_dir_systemd,
  ['.*/etc/systemd/system/.*%.d/.*%.conf'] = systemd_dir_systemd,
  ['.*/etc/systemd/system/.*%.d/%.#.*'] = systemd_dir_systemd,
  ['.*/etc/systemd/system/%.#.*'] = systemd_dir_systemd,
  ['.*/%.config/systemd/user/.*%.d/%.#.*'] = systemd_dir_systemd,
  ['.*/%.config/systemd/user/%.#.*'] = systemd_dir_systemd,
  ['.*termcap.*'] = starsetf(function(path, bufnr)
    return require('vim.filetype.detect').printcap('term')
  end),
  ['.*/tex/latex/.*%.cfg'] = { 'tex', fast_pattern.plain_dotcfg },
  ['.*%.t%.html'] = 'tilde',
  ['%.?tmux.*%.conf'] = { 'tmux', fast_pattern.plain_dotconf },
  ['%.?tmux.*%.conf.*'] = {
    'tmux',
    { priority = -1, fastpat = fast_pattern.plain_dotconf.fastpat },
  },
  ['.*/%.cargo/config'] = { 'toml', fast_pattern.dirstart_conf },
  ['.*/%.cargo/credentials'] = { 'toml', fast_pattern.dirstart_dot },
  ['.*/etc/udev/udev%.conf'] = { 'udevconf', fast_pattern.dir_etc },
  ['.*/etc/udev/permissions%.d/.*%.permissions'] = { 'udevperm', fast_pattern.dir_etc },
  ['.*/etc/updatedb%.conf'] = { 'updatedb', fast_pattern.dir_etc },
  ['.*/%.init/.*%.override'] = { 'upstart', fast_pattern.dirstart_dot },
  ['.*/usr/share/upstart/.*%.conf'] = { 'upstart', fast_pattern.dir_usr },
  ['.*/%.config/upstart/.*%.override'] = { 'upstart', fast_pattern.plain_dotconf },
  ['.*/etc/init/.*%.conf'] = { 'upstart', fast_pattern.dir_etc },
  ['.*/etc/init/.*%.override'] = { 'upstart', fast_pattern.dir_etc },
  ['.*/%.config/upstart/.*%.conf'] = { 'upstart', fast_pattern.plain_dotconf },
  ['.*/%.init/.*%.conf'] = { 'upstart', fast_pattern.plain_dotconf },
  ['.*/usr/share/upstart/.*%.override'] = { 'upstart', fast_pattern.dir_usr },
  ['.*%.[Ll][Oo][Gg]'] = detect.log,
  ['.*/etc/config/.*'] = starsetf(detect.uci, fast_pattern.dir_etc),
  ['.*%.vhdl_[0-9].*'] = starsetf('vhdl'),
  ['.*/Xresources/.*'] = starsetf('xdefaults'),
  ['.*/app%-defaults/.*'] = starsetf('xdefaults'),
  ['.*/etc/xinetd%.conf'] = { 'xinetd', fast_pattern.dir_etc },
  ['.*/usr/share/X11/xkb/compat/.*'] = starsetf('xkb', fast_pattern.dir_usr),
  ['.*/usr/share/X11/xkb/geometry/.*'] = starsetf('xkb', fast_pattern.dir_usr),
  ['.*/usr/share/X11/xkb/keycodes/.*'] = starsetf('xkb', fast_pattern.dir_usr),
  ['.*/usr/share/X11/xkb/symbols/.*'] = starsetf('xkb', fast_pattern.dir_usr),
  ['.*/usr/share/X11/xkb/types/.*'] = starsetf('xkb', fast_pattern.dir_usr),
  ['.*/etc/blkid%.tab'] = { 'xml', fast_pattern.dir_etc },
  ['.*/etc/blkid%.tab%.old'] = { 'xml', fast_pattern.dir_etc },
  ['.*%.vbproj%.user'] = { 'xml', fast_pattern.plain_projdotuser },
  ['.*%.fsproj%.user'] = { 'xml', fast_pattern.plain_projdotuser },
  ['.*%.csproj%.user'] = { 'xml', fast_pattern.plain_projdotuser },
  ['.*/etc/xdg/menus/.*%.menu'] = { 'xml', fast_pattern.dir_etc },
  ['.*Xmodmap'] = 'xmodmap',
  ['.*/etc/zprofile'] = { 'zsh', fast_pattern.dir_etc },
  ['.*vimrc.*'] = starsetf('vim'),
  ['Xresources.*'] = starsetf('xdefaults'),
  ['.*/etc/xinetd%.d/.*'] = starsetf('xinetd', fast_pattern.dir_etc),
  ['.*xmodmap.*'] = starsetf('xmodmap'),
  ['.*/xorg%.conf%.d/.*%.conf'] = { detect.xfree86_v4, fast_pattern.plain_dotconf },
  -- Increase priority to run before the pattern below
  ['XF86Config%-4.*'] = starsetf(detect.xfree86_v4, { priority = -math.huge + 1 }),
  ['XF86Config.*'] = starsetf(detect.xfree86_v3),
  ['.*/%.bundle/config'] = { 'yaml', fast_pattern.dirstart_conf },
  ['%.zcompdump.*'] = starsetf('zsh', fast_pattern.start_dot),
  -- .zlog* and zlog*
  ['%.?zlog.*'] = starsetf('zsh'),
  -- .zsh* and zsh*
  ['%.?zsh.*'] = starsetf('zsh'),
  -- Ignored extension
  ['.*~'] = function(path, bufnr)
    local short = path:gsub('~+$', '', 1)
    if path ~= short and short ~= '' then
      return M.match({ buf = bufnr, filename = fn.fnameescape(short) })
    end
  end,
  -- END PATTERN
}
-- luacheck: pop
-- luacheck: pop

local function compare_by_priority(a, b)
  return a[next(a)][2].priority > b[next(b)][2].priority
end

--- @param t vim.filetype.mapping
--- @return vim.filetype.mapping[]
--- @return vim.filetype.mapping[]
local function sort_by_priority(t)
  -- Separate patterns with non-negative and negative priority because they
  -- will be processed separately
  local pos = {} --- @type vim.filetype.mapping[]
  local neg = {} --- @type vim.filetype.mapping[]
  for k, v in pairs(t) do
    local ft = type(v) == 'table' and v[1] or v
    assert(
      type(ft) == 'string' or type(ft) == 'function',
      'Expected string or function for filetype'
    )

    local opts = (type(v) == 'table' and type(v[2]) == 'table') and v[2] or {}
    opts.fastpat = opts.fastpat or ''
    opts.priority = opts.priority or 0

    table.insert(opts.priority >= 0 and pos or neg, { [k] = { ft, opts } })
  end

  table.sort(pos, compare_by_priority)
  table.sort(neg, compare_by_priority)
  return pos, neg
end

local pattern_sorted_pos, pattern_sorted_neg = sort_by_priority(pattern)

--- @param path string
--- @param as_pattern? true
--- @return string
local function normalize_path(path, as_pattern)
  local normal = path:gsub('\\', '/')
  if normal:find('^~') then
    if as_pattern then
      -- Escape Lua's metacharacters when $HOME is used in a pattern.
      -- The rest of path should already be properly escaped.
      normal = vim.pesc(vim.env.HOME) .. normal:sub(2)
    else
      normal = vim.env.HOME .. normal:sub(2) --- @type string
    end
  end
  return normal
end

--- @class vim.filetype.add.filetypes
--- @inlinedoc
--- @field pattern? vim.filetype.mapping
--- @field extension? vim.filetype.mapping
--- @field filename? vim.filetype.mapping

--- Add new filetype mappings.
---
--- Filetype mappings can be added either by extension or by filename (either
--- the "tail" or the full file path). The full file path is checked first,
--- followed by the file name. If a match is not found using the filename, then
--- the filename is matched against the list of |lua-patterns| (sorted by priority)
--- until a match is found. Lastly, if pattern matching does not find a
--- filetype, then the file extension is used.
---
--- The filetype can be either a string (in which case it is used as the
--- filetype directly) or a function. If a function, it takes the full path and
--- buffer number of the file as arguments (along with captures from the matched
--- pattern, if any) and should return a string that will be used as the
--- buffer's filetype. Optionally, the function can return a second function
--- value which, when called, modifies the state of the buffer. This can be used
--- to, for example, set filetype-specific buffer variables. This function will
--- be called by Nvim before setting the buffer's filetype.
---
--- Filename patterns can specify an optional priority to resolve cases when a
--- file path matches multiple patterns. Higher priorities are matched first.
--- When omitted, the priority defaults to 0.
--- A pattern can contain environment variables of the form "${SOME_VAR}" that will
--- be automatically expanded. If the environment variable is not set, the pattern
--- won't be matched.
---
--- See $VIMRUNTIME/lua/vim/filetype.lua for more examples.
---
--- Example:
---
--- ```lua
--- vim.filetype.add({
---   extension = {
---     foo = 'fooscript',
---     bar = function(path, bufnr)
---       if some_condition() then
---         return 'barscript', function(bufnr)
---           -- Set a buffer variable
---           vim.b[bufnr].barscript_version = 2
---         end
---       end
---       return 'bar'
---     end,
---   },
---   filename = {
---     ['.foorc'] = 'toml',
---     ['/etc/foo/config'] = 'toml',
---   },
---   pattern = {
---     ['.*/etc/foo/.*'] = 'fooscript',
---     -- Using an optional priority
---     ['.*/etc/foo/.*%.conf'] = { 'dosini', { priority = 10 } },
---     -- A pattern containing an environment variable
---     ['${XDG_CONFIG_HOME}/foo/git'] = 'git',
---     ['README.(%a+)$'] = function(path, bufnr, ext)
---       if ext == 'md' then
---         return 'markdown'
---       elseif ext == 'rst' then
---         return 'rst'
---       end
---     end,
---   },
--- })
--- ```
---
--- To add a fallback match on contents, use
---
--- ```lua
--- vim.filetype.add {
---   pattern = {
---     ['.*'] = {
---       function(path, bufnr)
---         local content = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ''
---         if vim.regex([[^#!.*\\<mine\\>]]):match_str(content) ~= nil then
---           return 'mine'
---         elseif vim.regex([[\\<drawing\\>]]):match_str(content) ~= nil then
---           return 'drawing'
---         end
---       end,
---       { priority = -math.huge },
---     },
---   },
--- }
--- ```
---
---@param filetypes vim.filetype.add.filetypes A table containing new filetype maps (see example).
function M.add(filetypes)
  for k, v in pairs(filetypes.extension or {}) do
    extension[k] = v
  end

  for k, v in pairs(filetypes.filename or {}) do
    filename[normalize_path(k)] = v
  end

  for k, v in pairs(filetypes.pattern or {}) do
    pattern[normalize_path(k, true)] = v
  end

  if filetypes.pattern then
    pattern_sorted_pos, pattern_sorted_neg = sort_by_priority(pattern)
  end
end

--- @param ft vim.filetype.mapping.value
--- @param path? string
--- @param bufnr? integer
--- @param ... any
--- @return string?
--- @return fun(b: integer)?
local function dispatch(ft, path, bufnr, ...)
  if type(ft) == 'string' then
    return ft
  end

  if type(ft) ~= 'function' then
    return
  end

  assert(path)

  ---@type string|false?, fun(b: integer)?
  local ft0, on_detect
  if bufnr then
    ft0, on_detect = ft(path, bufnr, ...)
  else
    -- If bufnr is nil (meaning we are matching only against the filename), set it to an invalid
    -- value (-1) and catch any errors from the filetype detection function. If the function tries
    -- to use the buffer then it will fail, but this enables functions which do not need a buffer
    -- to still work.
    local ok
    ok, ft0, on_detect = pcall(ft, path, -1, ...)
    if not ok then
      return
    end
  end

  if not ft0 then
    return
  end

  return ft0, on_detect
end

--- Lookup table/cache for patterns
--- @alias vim.filetype.pattern_cache { fullpat: string, has_env: boolean, has_slash: boolean }
--- @type table<string,vim.filetype.pattern_cache>
local pattern_lookup = {}

--- @param pat string
--- @return vim.filetype.pattern_cache
local function parse_pattern(pat)
  pattern_lookup[pat] = {
    fullpat = '^' .. pat .. '$',
    has_env = pat:find('%$%b{}') ~= nil,
    has_slash = pat:find('/') ~= nil,
  }
  return pattern_lookup[pat]
end

--- @param pat string
--- @return boolean
--- @return string
local function expand_envvar_pattern(pat)
  local some_env_missing = false
  local expanded = pat:gsub('%${(%S-)}', function(env)
    local val = vim.env[env] --- @type string?
    some_env_missing = some_env_missing or val == nil
    return vim.pesc(val or '')
  end)
  return some_env_missing, expanded
end

--- @param name string
--- @param path string
--- @param tail string
--- @param pat string
--- @return string|boolean?
local function match_pattern(name, path, tail, pat)
  local pat_cache = pattern_lookup[pat] or parse_pattern(pat)
  local fullpat, has_slash = pat_cache.fullpat, pat_cache.has_slash

  if pat_cache.has_env then
    local some_env_missing, expanded = expand_envvar_pattern(fullpat)
    -- If any environment variable is present in the pattern but not set, there is no match
    if some_env_missing then
      return false
    end
    fullpat, has_slash = expanded, expanded:find('/') ~= nil
  end

  if has_slash then
    -- Similar to |autocmd-pattern|, if the pattern contains a '/' then check for a match against
    -- both the short file name (as typed) and the full file name (after expanding to full path
    -- and resolving symlinks)
    return (name:match(fullpat) or path:match(fullpat))
  end

  return (tail:match(fullpat))
end

--- Cache for whether current candidates match fast patterns.
--- Need to be manually reset in every new `M.match()` call.
--- @type table<string,boolean>
local fast_matches = {}

--- @param name string
--- @param path string
--- @param tail string
--- @param pat string
--- @return boolean
local function match_fastpat(name, path, tail, pat)
  -- Prefer cached match result (a.k.a. the core reason of fast patterns speedup)
  if fast_matches[pat] ~= nil then
    return fast_matches[pat]
  end

  local pat_cache = pattern_lookup[pat] or parse_pattern(pat)
  if pat_cache.has_env then
    local some_env_missing, expanded = expand_envvar_pattern(pat)
    if some_env_missing then
      fast_matches[pat] = false
      return false
    end
    pat = expanded
  end
  -- Try all possible candidates to make all kins of fast patterns work
  fast_matches[pat] = (path:match(pat) or name:match(pat) or tail:match(pat)) ~= nil
  return fast_matches[pat]
end

--- @param name string
--- @param path string
--- @param tail string
--- @param pattern_sorted vim.filetype.mapping[]
--- @param bufnr integer?
local function match_pattern_sorted(name, path, tail, pattern_sorted, bufnr)
  for i = 1, #pattern_sorted do
    local pat, ft_data = next(pattern_sorted[i])
    if match_fastpat(name, path, tail, ft_data[2].fastpat) then
      local matches = match_pattern(name, path, tail, pat)
      if matches then
        local ft, on_detect = dispatch(ft_data[1], path, bufnr, matches)
        if ft then
          return ft, on_detect
        end
      end
    end
  end
end

--- @class vim.filetype.match.args
--- @inlinedoc
---
--- Buffer number to use for matching. Mutually exclusive with {contents}
--- @field buf? integer
---
--- Filename to use for matching. When {buf} is given,
--- defaults to the filename of the given buffer number. The
--- file need not actually exist in the filesystem. When used
--- without {buf} only the name of the file is used for
--- filetype matching. This may result in failure to detect
--- the filetype in cases where the filename alone is not
--- enough to disambiguate the filetype.
--- @field filename? string
---
--- An array of lines representing file contents to use for
--- matching. Can be used with {filename}. Mutually exclusive
--- with {buf}.
--- @field contents? string[]

--- Perform filetype detection.
---
--- The filetype can be detected using one of three methods:
--- 1. Using an existing buffer
--- 2. Using only a file name
--- 3. Using only file contents
---
--- Of these, option 1 provides the most accurate result as it uses both the buffer's filename and
--- (optionally) the buffer contents. Options 2 and 3 can be used without an existing buffer, but
--- may not always provide a match in cases where the filename (or contents) cannot unambiguously
--- determine the filetype.
---
--- Each of the three options is specified using a key to the single argument of this function.
--- Example:
---
--- ```lua
--- -- Using a buffer number
--- vim.filetype.match({ buf = 42 })
---
--- -- Override the filename of the given buffer
--- vim.filetype.match({ buf = 42, filename = 'foo.c' })
---
--- -- Using a filename without a buffer
--- vim.filetype.match({ filename = 'main.lua' })
---
--- -- Using file contents
--- vim.filetype.match({ contents = {'#!/usr/bin/env bash'} })
--- ```
---
---@param args vim.filetype.match.args Table specifying which matching strategy to use.
---                 Accepted keys are:
---@return string|nil # If a match was found, the matched filetype.
---@return function|nil # A function that modifies buffer state when called (for example, to set some
---                     filetype specific buffer variables). The function accepts a buffer number as
---                     its only argument.
function M.match(args)
  vim.validate({
    arg = { args, 't' },
  })

  if not (args.buf or args.filename or args.contents) then
    error('At least one of "buf", "filename", or "contents" must be given')
  end

  local bufnr = args.buf
  local name = args.filename
  local contents = args.contents

  if bufnr and not name then
    name = api.nvim_buf_get_name(bufnr)
  end

  --- @type string?, fun(b: integer)?
  local ft, on_detect

  if name then
    name = normalize_path(name)

    -- First check for the simple case where the full path exists as a key
    local path = fn.fnamemodify(name, ':p')
    ft, on_detect = dispatch(filename[path], path, bufnr)
    if ft then
      return ft, on_detect
    end

    -- Next check against just the file name
    local tail = fn.fnamemodify(name, ':t')
    ft, on_detect = dispatch(filename[tail], path, bufnr)
    if ft then
      return ft, on_detect
    end

    -- Next, check the file path against available patterns with non-negative priority
    fast_matches = {}
    ft, on_detect = match_pattern_sorted(name, path, tail, pattern_sorted_pos, bufnr)
    if ft then
      return ft, on_detect
    end

    -- Next, check file extension
    -- Don't use fnamemodify() with :e modifier here,
    -- as that's empty when there is only an extension.
    local ext = name:match('%.([^.]-)$') or ''
    ft, on_detect = dispatch(extension[ext], path, bufnr)
    if ft then
      return ft, on_detect
    end

    -- Next, check patterns with negative priority
    ft, on_detect = match_pattern_sorted(name, path, tail, pattern_sorted_neg, bufnr)
    if ft then
      return ft, on_detect
    end
  end

  -- Finally, check file contents
  if contents or bufnr then
    if contents == nil then
      assert(bufnr)
      if api.nvim_buf_line_count(bufnr) > 101 then
        -- only need first 100 and last line for current checks
        contents = M._getlines(bufnr, 1, 100)
        contents[#contents + 1] = M._getline(bufnr, -1)
      else
        contents = M._getlines(bufnr)
      end
    end

    -- Match based solely on content only if there is any content (for performance)
    if not (#contents == 1 and contents[1] == '') then
      -- If name is nil, catch any errors from the contents filetype detection function.
      -- If the function tries to use the filename that is nil then it will fail,
      -- but this enables checks which do not need a filename to still work.
      local ok
      ok, ft, on_detect = pcall(
        require('vim.filetype.detect').match_contents,
        contents,
        name,
        function(ext)
          return dispatch(extension[ext], name, bufnr)
        end
      )
      if ok then
        return ft, on_detect
      end
    end
  end
end

--- Get the default option value for a {filetype}.
---
--- The returned value is what would be set in a new buffer after 'filetype'
--- is set, meaning it should respect all FileType autocmds and ftplugin files.
---
--- Example:
---
--- ```lua
--- vim.filetype.get_option('vim', 'commentstring')
--- ```
---
--- Note: this uses |nvim_get_option_value()| but caches the result.
--- This means |ftplugin| and |FileType| autocommands are only
--- triggered once and may not reflect later changes.
--- @param filetype string Filetype
--- @param option string Option name
--- @return string|boolean|integer: Option value
function M.get_option(filetype, option)
  return require('vim.filetype.options').get_option(filetype, option)
end

return M
