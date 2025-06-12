--- @brief
---
---WORK IN PROGRESS built-in plugin manager! Early testing of existing features
---is appreciated, but expect breaking changes without notice.
---
---Manages plugins only in a dedicated [vim.pack-directory]() (see |packages|):
---`$XDG_DATA_HOME/nvim/site/pack/core/opt`.
---Plugin's subdirectory name matches plugin's name in specification.
---It is assumed that all plugins in the directory are managed exclusively by `vim.pack`.
---
---Uses Git to manage plugins and requires present `git` executable of at
---least version 2.36. Target plugins should be Git repositories with versions
---as named tags following semver convention `v<major>.<minor>.<patch>`.
---
---Example workflows ~
---
---Basic install and management:
---
---- Add |vim.pack.add()| call(s) to 'init.lua':
---```lua
---
---vim.pack.add({
---   -- Install "plugin1" and use default branch (usually `main` or `master`)
---   'https://github.com/user/plugin1',
---
---   -- Same as above, but using a table (allows setting other options)
---   { source = 'https://github.com/user/plugin1' },
---
---   -- Specify plugin's name (here the plugin will be called "plugin2"
---   -- instead of "generic-name")
---   { source = 'https://github.com/user/generic-name', name = 'plugin2' },
---
---   -- Specify version to follow during install and update
---   {
---     source = 'https://github.com/user/plugin3',
---     -- Version constraint, see |vim.version.range()|
---     version = vim.version.range('1.0'),
---   },
---   {
---     source = 'https://github.com/user/plugin4',
---     -- Git branch, tag, or commit hash
---     version = 'main',
---   },
---})
---
----- Plugin's code can be used directly after `add()`
---plugin1 = require('plugin1')
---```
---
---- Restart Nvim (for example, with |:restart|). Plugins that were not yet
---installed will be available on disk in target state after `add()` call.
---
---- To update all plugins with new changes:
---    - Execute |vim.pack.update()|. This will download updates from source and
---      show confirmation buffer in a separate tabpage.
---    - Review changes. To confirm all updates execute |:write|.
---      To discard updates execute |:quit|.
---
---Switch plugin's version:
---- Update 'init.lua' for plugin to have desired `version`. Let's say, plugin
---named 'plugin1' has changed to `vim.version.range('*')`.
---- |:restart|. The plugin's actual state on disk is not yet changed.
---- Execute `vim.pack.update({ 'plugin1' })`.
---- Review changes and either confirm or discard them. If discarded, revert
---any changes in 'init.lua' as well or you will be prompted again next time
---you run |vim.pack.update()|.
---
---Freeze plugin from being updated:
---- Update 'init.lua' for plugin to have `version` set to current commit hash.
---You can get it by running `vim.pack.update({ 'plugin-name' })` and yanking
---the word describing current state (looks like `abc12345`).
---- |:restart|.
---
---Unfreeze plugin to start receiving updates:
---- Update 'init.lua' for plugin to have `version` set to whichever version
---you want it to be updated.
---- |:restart|.
---
---Remove plugins from disk:
---- Use |vim.pack.del()| with a list of plugin names to remove. Make sure their specs
---are not included in |vim.pack.add()| call in 'init.lua' or they will be reinstalled.
---
--- Available events to hook into ~
---
---- [PackInstallPre]() - before trying to install plugin on disk.
---- [PackInstall]() - after installing plugin on disk in proper state.
---After |PackUpdatePre| and |PackUpdate|.
---- [PackUpdatePre]() - before trying to update plugin's state.
---- [PackUpdate]() - after plugin's state is updated.
---- [PackDeletePre]() - before removing plugin from disk.
---- [PackDelete]() - after removing plugin from disk.

local api = vim.api
local uv = vim.uv
local async = require('vim._async')

local M = {}

-- Git ------------------------------------------------------------------------
--- @async
--- @param cmd string[]
--- @param cwd string
--- @return string
local function cli_async(cmd, cwd)
  local sys_opts = { cwd = cwd, text = true, clear_env = true }
  local out = async.await(3, vim.system, cmd, sys_opts) --- @type vim.SystemCompleted
  async.await(1, vim.schedule)
  if out.code ~= 0 then
    error(out.stderr)
  end
  if out.stderr ~= '' then
    vim.schedule(function()
      vim.notify(out.stderr:gsub('\n+$', ''), vim.log.levels.WARN)
    end)
  end
  return (out.stdout:gsub('\n+$', ''))
end

local function git_ensure_exec()
  if vim.fn.executable('git') == 0 then
    error('No `git` executable')
  end
end

--- @type table<string,fun(...): string[]>
local git_args = {
  clone = function(source, path)
    -- NOTE: '--also-filter-submodules' requires Git>=2.36
    local opts = { '--filter=blob:none', '--recurse-submodules', '--also-filter-submodules' }
    if vim.startswith(source, 'file://') then
      opts = { '--no-hardlinks' }
    end
    return { 'clone', '--quiet', unpack(opts), '--origin', 'origin', source, path }
  end,
  --- @param timestamp string
  stash = function(timestamp)
    local msg = '(vim.pack) ' .. timestamp .. ' Stash before checkout'
    return { 'stash', '--quiet', '--message', msg }
  end,
  checkout = function(target)
    return { 'checkout', '--quiet', target }
  end,
  -- Using '--tags --force' means conflicting tags will be synced with remote
  fetch = function()
    return { 'fetch', '--quiet', '--tags', '--force', '--recurse-submodules=yes', 'origin' }
  end,
  get_origin = function()
    return { 'remote', 'get-url', 'origin' }
  end,
  get_default_origin_branch = function()
    return { 'rev-parse', '--abbrev-ref', 'origin/HEAD' }
  end,
  -- Using `rev-list -1` shows a commit of revision, while `rev-parse` shows
  -- hash of revision. Those are different for annotated tags.
  get_hash = function(rev)
    return { 'rev-list', '-1', '--abbrev-commit', rev }
  end,
  log = function(from, to)
    local pretty = '--pretty=format:%m %h │ %s%d'
    -- `--topo-order` makes showing divergent branches nicer
    -- `--decorate-refs` shows only tags near commits (not `origin/main`, etc.)
    return { 'log', pretty, '--topo-order', '--decorate-refs=refs/tags', from .. '...' .. to }
  end,
  list_branches = function()
    return { 'branch', '--remote', '--list', '--format=%(refname:short)', '--', 'origin/**' }
  end,
  list_tags = function()
    return { 'tag', '--list', '--sort=-v:refname' }
  end,
  list_new_tags = function(from)
    return { 'tag', '--list', '--sort=-v:refname', '--contains', from }
  end,
  list_cur_tags = function(at)
    return { 'tag', '--list', '--points-at', at }
  end,
}

local function git_cmd(cmd_name, ...)
  local args = git_args[cmd_name](...)
  if args == nil then
    return {}
  end

  -- Use '-c gc.auto=0' to disable `stderr` "Auto packing..." messages
  return { 'git', '-c', 'gc.auto=0', unpack(args) }
end

--- @async
local function git_get_default_branch(cwd)
  local res = cli_async(git_cmd('get_default_origin_branch'), cwd)
  return (res:gsub('^origin/', ''))
end

--- @async
--- @param cwd string
local function git_get_branches(cwd)
  local stdout = cli_async(git_cmd('list_branches'), cwd)
  local res = {}
  for _, l in ipairs(vim.split(stdout, '\n')) do
    table.insert(res, l:match('^origin/(.+)$'))
  end
  return res
end

--- @async
--- @param cwd string
local function git_get_tags(cwd)
  local stdout = cli_async(git_cmd('list_tags'), cwd)
  return vim.split(stdout, '\n')
end

-- Plugin operations ----------------------------------------------------------
local function get_plug_dir()
  return vim.fs.joinpath(vim.fn.stdpath('data'), 'site', 'pack', 'core', 'opt')
end

--- @param msg string|string[]
--- @param level ('DEBUG'|'TRACE'|'INFO'|'WARN'|'ERROR')?
local function notify(msg, level)
  msg = type(msg) == 'table' and table.concat(msg, '\n') or msg
  vim.notify('(vim.pack) ' .. msg, vim.log.levels[level or 'INFO'])
  vim.cmd.redraw()
end

local function is_version_range(x)
  return (pcall(function()
    x:has('1')
  end))
end

local function get_timestamp()
  return vim.fn.strftime('%Y-%m-%d %H:%M:%S')
end

--- @class vim.pack.Spec
---
--- URI from which to install and pull updates. Any format supported by `git clone` is allowed.
--- @field source string
---
--- Name of plugin. Will be used as directory name. Default: `source` repository name.
--- @field name? string
---
--- Version to use for install and updates. Can be:
--- - `nil` (no value, default) to use repository's default branch (usually `main` or `master`).
--- - String to use specific branch, tag, or commit hash.
--- - Output of |vim.version.range()| to install the greatest/last semver tag
---   inside the version constraint.
--- @field version? string|vim.VersionRange

--- @alias vim.pack.SpecResolved { source: string, name: string, version: nil|string|vim.VersionRange }

--- @param spec string|vim.pack.Spec
--- @return vim.pack.SpecResolved
local function normalize_spec(spec)
  spec = type(spec) == 'string' and { source = spec } or spec
  vim.validate('spec', spec, 'table')
  vim.validate('spec.source', spec.source, 'string')
  local name = (spec.name or spec.source:gsub('%.git$', '')):match('[^/]+$')
  vim.validate('spec.name', name, 'string')
  local function is_version(x)
    return type(x) == 'string' or is_version_range(x)
  end
  vim.validate('spec.version', spec.version, is_version, true, 'string or vim.VersionRange')
  return { source = spec.source, name = name, version = spec.version }
end

--- @class (private) vim.pack.PlugInfo
--- @field err string The latest error when working on plugin. If non-empty,
---   all further actions should not be done (including triggering events).
--- @field did_install? boolean Whether plugin was successfully installed.
--- @field version_str? string `spec.version` with resolved version range.
--- @field version_ref? string Resolved version as Git reference (if different
---   from `version_str`).
--- @field sha_head? string Git hash of HEAD.
--- @field sha_target? string Git hash of `version_ref`.
--- @field update_details? string Details about the update:: changelog if HEAD
---   and target are different, available newer tags otherwise.

--- @class (private) vim.pack.Plug
--- @field spec vim.pack.SpecResolved
--- @field path string
--- @field info vim.pack.PlugInfo Gathered information about plugin.

--- @param spec string|vim.pack.Spec
--- @return vim.pack.Plug
local function new_plug(spec)
  local spec_resolved = normalize_spec(spec)
  local path = vim.fs.joinpath(get_plug_dir(), spec_resolved.name)
  return { spec = spec_resolved, path = path, info = { err = '' } }
end

--- Normalize plug array: gather non-conflicting data from duplicated entries.
--- @param plugs vim.pack.Plug[]
--- @return vim.pack.Plug[]
local function normalize_plugs(plugs)
  --- @type table<string, { plug: vim.pack.Plug, id: integer }>
  local plug_map = {}
  local n = 0
  for _, p in ipairs(plugs) do
    -- Collect
    local p_data = plug_map[p.path]
    if p_data == nil then
      n = n + 1
      plug_map[p.path] = { plug = p, id = n }
      p_data = plug_map[p.path]
    end
    -- TODO(echasnovski): if both versions are `vim.VersionRange`, collect as
    -- their intersection. Needs `vim.version.intersect`.
    p_data.plug.spec.version = vim.F.if_nil(p_data.plug.spec.version, p.spec.version)

    -- Ensure no conflicts
    local spec_ref = p_data.plug.spec
    local spec = p.spec
    if spec_ref.source ~= spec.source then
      local src_1 = tostring(spec_ref.source)
      local src_2 = tostring(spec.source)
      error(('Conflicting `source` for `%s`:\n%s\n%s'):format(spec.name, src_1, src_2))
    end
    if spec_ref.version ~= spec.version then
      local ver_1 = tostring(spec_ref.version)
      local ver_2 = tostring(spec.version)
      error(('Conflicting `version` for `%s`:\n%s\n%s'):format(spec.name, ver_1, ver_2))
    end
  end

  --- @type vim.pack.Plug[]
  local res = {}
  for _, p_data in pairs(plug_map) do
    res[p_data.id] = p_data.plug
  end
  return res
end

--- @param names string[]?
--- @return vim.pack.Plug[]
local function plug_list_from_names(names)
  local all_plugins = M.get()
  local plugs = {}
  -- Preserve plugin order; might be important during checkout or event trigger
  for _, p_data in ipairs(all_plugins) do
    -- NOTE: By default include only added plugins (and not all on disk). Using
    -- not added plugins might lead to a confusion as default `version` and
    -- user's desired one might mismatch.
    -- TODO(echasnovski): Consider changing this if/when there is lockfile.
    --- @cast names string[]
    if (names == nil and p_data.was_added) or vim.tbl_contains(names or {}, p_data.spec.name) then
      table.insert(plugs, new_plug(p_data.spec))
    end
  end

  return plugs
end

--- @param p vim.pack.Plug
--- @param event_name 'PackInstallPre'|'PackInstall'|'PackUpdatePre'|'PackUpdate'|'PackDeletePre'|'PackDelete'
local function trigger_event(p, event_name)
  local data = { spec = vim.deepcopy(p.spec), path = p.path }
  vim.api.nvim_exec_autocmds(event_name, { pattern = p.path, data = data })
end

--- @param title string
--- @return fun(kind: 'begin'|'report'|'end', msg: string?, percent: integer?): nil
local function new_progress_report(title)
  -- TODO(echasnovski): currently print directly in command line because
  -- there is no robust built-in way of showing progress:
  -- - `vim.ui.progress()` is planned and is a good candidate to use here.
  -- - Use `'$/progress'` implementation in 'vim.pack._lsp' if there is
  --   a working built-in '$/progress' handler. Something like this:
  --   ```lua
  --   local progress_token_count = 0
  --   function M.new_progress_report(title)
  --     progress_token_count = progress_token_count + 1
  --     return vim.schedule_wrap(function(kind, msg, percent)
  --       local value = { kind = kind, message = msg, percentage = percent }
  --       dispatchers.notification(
  --         '$/progress',
  --         { token = progress_token_count, value = value }
  --       )
  --     end
  --   end
  --   ```
  -- Any of these choices is better as users can tweak how progress is shown.

  return vim.schedule_wrap(function(kind, msg, percent)
    local progress = kind == 'end' and 'done' or ('%3d%%'):format(percent)
    print(('%s: %s %s'):format(progress, title, msg))
    -- Force redraw to show installation progress during startup
    vim.cmd.redraw({ bang = true })
  end)
end

--- Execute function in parallel for each non-errored plugin in the list
--- @param plug_list vim.pack.Plug[]
--- @param f async fun(p: vim.pack.Plug): nil
--- @param progress_title? string
local function run_list(plug_list, f, progress_title)
  local n_threads = 2 * #(uv.cpu_info() or { {} })
  local report_progress = progress_title ~= nil and new_progress_report(progress_title)
    or function(_, _, _) end

  -- Construct array of functions to execute in parallel
  local n_finished = 0
  local funs = {} --- @type (async fun())[]
  for _, p in ipairs(plug_list) do
    -- Run only for plugins which didn't error before
    if p.info.err == '' then
      --- @async
      funs[#funs + 1] = function()
        local ok, err = pcall(f, p)
        if not ok then
          p.info.err = err --[[@as string]]
        end

        -- Show progress
        n_finished = n_finished + 1
        local percent = math.floor(100 * n_finished / #funs)
        local msg = ('(%d/%d) - %s'):format(n_finished, #funs, p.spec.name)
        report_progress('report', msg, percent)
      end
    end
  end

  if #funs == 0 then
    return
  end

  -- Run async in parallel but wait for all to finish/timeout
  local begin_msg = ('(0/%d)'):format(#funs)
  report_progress('begin', begin_msg, 0)

  --- @async
  local function joined_f()
    async.join(n_threads, funs)
  end
  async.run(joined_f):wait()

  local end_msg = ('(%d/%d)'):format(#funs, #funs)
  report_progress('end', end_msg, 100)
end

--- @param msg string
local function confirm(msg)
  -- Work around confirmation message not showing during startup.
  -- This is a semi-regression of #31525: some redraw during startup makes
  -- confirmation message disappear.
  -- TODO: Remove when #34088 is resolved.
  if vim.v.vim_did_enter == 1 then
    return vim.fn.confirm(msg, 'Proceed? &Yes\n&No', 1, 'Question') == 1
  end

  msg = msg .. '\nProceed? [Y]es, (N)o'
  vim.defer_fn(function()
    vim.print(msg)
  end, 100)
  local ok, char = pcall(vim.fn.getcharstr)
  local res = (ok and (char == 'y' or char == 'Y' or char == '\r')) and 1 or 0
  vim.cmd.redraw()
  return res == 1
end

--- @async
--- @param p vim.pack.Plug
local function clone(p)
  cli_async(git_cmd('clone', p.spec.source, p.path), uv.cwd() or '')
  p.info.did_install = true
end

--- @async
--- @param p vim.pack.Plug
local function resolve_version(p)
  local function list_in_line(name, list)
    return #list == 0 and '' or ('\n' .. name .. ': ' .. table.concat(list, ', '))
  end

  -- Resolve only once
  if p.info.version_str ~= nil then
    return
  end
  local version = p.spec.version

  -- Default branch
  if version == nil then
    p.info.version_str = git_get_default_branch(p.path)
    p.info.version_ref = 'origin/' .. p.info.version_str
    return
  end

  -- Non-version-range like version: branch, tag, or commit hash
  local branches = git_get_branches(p.path)
  local tags = git_get_tags(p.path)
  if type(version) == 'string' then
    local is_branch = vim.tbl_contains(branches, version)
    local is_tag_or_hash = pcall(cli_async, git_cmd('get_hash', version), p.path)
    if not (is_branch or is_tag_or_hash) then
      local err = ('`%s` is not a branch/tag/commit. Available:'):format(version)
        .. list_in_line('Tags', tags)
        .. list_in_line('Branches', branches)
      error(err)
    end

    p.info.version_str = version
    p.info.version_ref = (is_branch and 'origin/' or '') .. version
    return
  end
  --- @cast version vim.VersionRange

  -- Choose the greatest/last version among all matching semver tags
  local last_ver_tag, semver_tags = nil, {}
  for _, tag in ipairs(tags) do
    local ver_tag = vim.version.parse(tag)
    table.insert(semver_tags, ver_tag ~= nil and tag or nil)
    local is_in_range = ver_tag and version:has(ver_tag)
    if is_in_range and (not last_ver_tag or ver_tag > last_ver_tag) then
      p.info.version_str, last_ver_tag = tag, ver_tag
    end
  end

  if p.info.version_str == nil then
    local err = 'No versions fit constraint. Relax it or switch to branch. Available:'
      .. list_in_line('Versions', semver_tags)
      .. list_in_line('Branches', branches)
    error(err)
  end
end

--- @async
--- @param p vim.pack.Plug
local function infer_states(p)
  p.info.sha_head = p.info.sha_head or cli_async(git_cmd('get_hash', 'HEAD'), p.path)

  resolve_version(p)
  local target_ref = p.info.version_ref or p.info.version_str --[[@as string]]
  p.info.sha_target = p.info.sha_target or cli_async(git_cmd('get_hash', target_ref), p.path)
end

--- Keep repos in detached HEAD state. Infer commit from resolved version.
--- No local branches are created, branches from "origin" remote are used directly.
--- @async
--- @param p vim.pack.Plug
--- @param opts { timestamp: string, skip_same_sha: boolean, silent: boolean }
local function checkout(p, opts)
  infer_states(p)
  if opts.skip_same_sha and p.info.sha_head == p.info.sha_target then
    return
  end

  trigger_event(p, 'PackUpdatePre')

  cli_async(git_cmd('stash', opts.timestamp), p.path)

  cli_async(git_cmd('checkout', p.info.sha_target), p.path)
  if not opts.silent then
    notify(('Updated state to `%s` in `%s`'):format(p.info.version_str, p.spec.name), 'INFO')
  end

  trigger_event(p, 'PackUpdate')

  -- (Re)Generate help tags according to the current help files.
  -- Also use `pcall()` because `:helptags` errors if there is no 'doc/'
  -- directory or if it is empty.
  local doc_dir = vim.fs.joinpath(p.path, 'doc')
  vim.fn.delete(vim.fs.joinpath(doc_dir, 'tags'))
  pcall(vim.cmd.helptags, vim.fn.fnameescape(doc_dir))
end

--- @param plug_list vim.pack.Plug[]
local function install_list(plug_list)
  -- Get user confirmation to install plugins
  local sources = {}
  for _, p in ipairs(plug_list) do
    table.insert(sources, p.spec.source)
  end
  local sources_str = table.concat(sources, '\n')
  local confirm_msg = ('These plugins will be installed:\n\n%s\n'):format(sources_str)
  if not confirm(confirm_msg) then
    for _, p in ipairs(plug_list) do
      p.info.err = 'Installation was not confirmed'
    end
    return
  end

  local checkout_opts = { timestamp = get_timestamp(), skip_same_sha = false, silent = true }
  --- @async
  --- @param p vim.pack.Plug
  local function do_install(p)
    trigger_event(p, 'PackInstallPre')

    clone(p)

    -- Do not skip checkout even if HEAD and target have same commit hash to
    -- have new repo in expected detached HEAD state and generated help files.
    checkout(p, checkout_opts)

    -- 'PackInstall' is triggered after 'PackUpdate' intentionally to have it
    -- indicate "plugin is installed in its correct initial version"
    trigger_event(p, 'PackInstall')
  end
  run_list(plug_list, do_install, 'Installing plugins')
end

--- @async
--- @param p vim.pack.Plug
local function infer_update_details(p)
  infer_states(p)

  local from = p.info.sha_head
  local to = p.info.sha_target
  local cmd = from ~= to and git_cmd('log', from, to) or git_cmd('list_new_tags', to)
  p.info.update_details = cli_async(cmd, p.path)

  if p.info.sha_head ~= p.info.sha_target or p.info.update_details == '' then
    return
  end

  -- Remove tags pointing at target (there might be several)
  local cur_tags = cli_async(git_cmd('list_cur_tags', p.info.sha_target), p.path)
  local cur_tags_arr = vim.split(cur_tags, '\n')
  local new_tags_arr = vim.split(p.info.update_details, '\n')
  local function is_not_cur_tag(s)
    return not vim.tbl_contains(cur_tags_arr, s)
  end
  p.info.update_details = table.concat(vim.tbl_filter(is_not_cur_tag, new_tags_arr), '\n')
end

--- Map from plugin path to its data.
--- Use map and not array to avoid linear lookup during startup.
--- @type table<string, { plug: vim.pack.Plug, id: integer }>
local added_plugins = {}
local n_added_plugins = 0

--- @param plug vim.pack.Plug
--- @param bang boolean
local function pack_add(plug, bang)
  -- Add plugin only once, i.e. no overriding of spec. This allows users to put
  -- plugin first to fully control its spec.
  if added_plugins[plug.path] ~= nil then
    return
  end

  n_added_plugins = n_added_plugins + 1
  added_plugins[plug.path] = { plug = plug, id = n_added_plugins }

  vim.cmd.packadd({ plug.spec.name, bang = bang })

  -- Execute 'after/' scripts if not during startup (when they will be sourced
  -- automatically), as `:packadd` only sources plain 'plugin/' files.
  -- See https://github.com/vim/vim/issues/15584
  -- Deliberately do so after executing all currently known 'plugin/' files.
  local should_load_after_dir = vim.v.vim_did_enter == 1 and not bang and vim.o.loadplugins
  if should_load_after_dir then
    local after_paths = vim.fn.glob(plug.path .. '/after/plugin/**/*.{vim,lua}', false, true)
    --- @param path string
    vim.tbl_map(function(path)
      pcall(vim.cmd.source, vim.fn.fnameescape(path))
    end, after_paths)
  end
end

--- @class vim.pack.keyset.add
--- @inlinedoc
--- @field bang? boolean Whether to execute `:packadd!` instead of |:packadd|. Default `false`.

--- Add plugin to current session
---
--- - For each specification check that plugin exists on disk in |vim.pack-directory|:
---     - If exists, do nothin in this step.
---     - If doesn't exist, install it by downloading from `source` into `name`
---       subdirectory (via `git clone`) and update state to match `version` (via `git checkout`).
--- - For each plugin execute |:packadd| making them reachable by Nvim.
---
--- Notes:
--- - Installation is done in parallel, but waits for all to finish before
---   continuing next code execution.
--- - If plugin is already present on disk, there are no checks about its present state.
---   The specified `version` can be not the one actually present on disk.
---   Execute |vim.pack.update()| to synchronize.
--- - Adding plugin second and more times during single session does nothing:
---   only the data from the first adding is registered.
---
--- @param specs (string|vim.pack.Spec)[] List of plugin specifications. String item
--- is treated as `source`.
--- @param opts? vim.pack.keyset.add
function M.add(specs, opts)
  vim.validate('specs', specs, vim.islist, false, 'list')
  opts = vim.tbl_extend('force', { bang = false }, opts or {})
  vim.validate('opts', opts, 'table')

  --- @type vim.pack.Plug[]
  local plugs = vim.tbl_map(new_plug, specs)
  plugs = normalize_plugs(plugs)

  -- Install
  --- @param p vim.pack.Plug
  local plugs_to_install = vim.tbl_filter(function(p)
    return uv.fs_stat(p.path) == nil
  end, plugs)

  if #plugs_to_install > 0 then
    git_ensure_exec()
    install_list(plugs_to_install)
  end
  local failed_install = {} --- @type table<string,boolean>
  for _, p in ipairs(plugs_to_install) do
    failed_install[p.spec.name] = not p.info.did_install
  end

  -- Register and `:packadd` those actually on disk
  for _, p in ipairs(plugs) do
    if not failed_install[p.spec.name] then
      pack_add(p, opts.bang)
    end
  end

  -- Delay showing errors to have "good" plugins added first
  for _, p in ipairs(plugs_to_install) do
    if p.info.err ~= '' then
      error(('Error in `%s` during installation:\n%s'):format(p.spec.name, p.info.err))
    end
  end
end

--- @param p vim.pack.Plug
--- @return string
local function compute_feedback_lines_single(p)
  if p.info.err ~= '' then
    return ('## %s\n\n %s'):format(p.spec.name, p.info.err:gsub('\n', '\n  '))
  end

  local parts = { '## ' .. p.spec.name .. '\n' }
  local version_suffix = p.info.version_str == '' and '' or (' (%s)'):format(p.info.version_str)

  if p.info.sha_head == p.info.sha_target then
    parts[#parts + 1] = table.concat({
      'Path:   ' .. p.path,
      'Source: ' .. p.spec.source,
      'State:  ' .. p.info.sha_target .. version_suffix,
    }, '\n')

    if p.info.update_details ~= '' then
      local details = p.info.update_details:gsub('\n', '\n• ')
      parts[#parts + 1] = '\n\nAvailable newer tags:\n• ' .. details
    end
  else
    parts[#parts + 1] = table.concat({
      'Path:         ' .. p.path,
      'Source:       ' .. p.spec.source,
      'State before: ' .. p.info.sha_head,
      'State after:  ' .. p.info.sha_target .. version_suffix,
      '',
      'Pending updates:',
      p.info.update_details,
    }, '\n')
  end

  return table.concat(parts, '')
end

--- @param plug_list vim.pack.Plug[]
--- @param skip_same_sha boolean
--- @return string[]
local function compute_feedback_lines(plug_list, skip_same_sha)
  -- Construct plugin line groups for better report
  local report_err, report_update, report_same = {}, {}, {}
  for _, p in ipairs(plug_list) do
    local group_arr = p.info.err ~= '' and report_err
      or (p.info.sha_head ~= p.info.sha_target and report_update or report_same)
    table.insert(group_arr, compute_feedback_lines_single(p))
  end

  local lines = {}
  --- @param header string
  --- @param arr string[]
  local function append_report(header, arr)
    if #arr == 0 then
      return
    end
    header = header .. ' ' .. string.rep('─', 79 - header:len())
    table.insert(lines, header)
    vim.list_extend(lines, arr)
  end
  append_report('# Error', report_err)
  append_report('# Update', report_update)
  if not skip_same_sha then
    append_report('# Same', report_same)
  end

  return vim.split(table.concat(lines, '\n\n'), '\n')
end

--- @param plug_list vim.pack.Plug[]
local function feedback_log(plug_list)
  local lines = compute_feedback_lines(plug_list, true)
  local title = ('========== Update %s =========='):format(get_timestamp())
  table.insert(lines, 1, title)
  table.insert(lines, '')

  local log_path = vim.fn.stdpath('log') .. '/nvimpack.log'
  vim.fn.mkdir(vim.fs.dirname(log_path), 'p')
  vim.fn.writefile(lines, log_path, 'a')
end

--- @param lines string[]
--- @param on_finish fun()
local function show_confirm_buf(lines, on_finish)
  -- Show buffer in a separate tabpage
  local bufnr = api.nvim_create_buf(true, true)
  api.nvim_buf_set_name(bufnr, 'nvimpack://' .. bufnr .. '/confirm-update')
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.cmd.sbuffer({ bufnr, mods = { tab = vim.fn.tabpagenr('#') } })
  local tab_num = api.nvim_tabpage_get_number(0)
  local win_id = api.nvim_get_current_win()

  local delete_buffer = vim.schedule_wrap(function()
    pcall(api.nvim_buf_delete, bufnr, { force = true })
    pcall(vim.cmd.tabclose, tab_num)
    vim.cmd.redraw()
  end)

  -- Define action on accepting confirm
  local function finish()
    on_finish()
    delete_buffer()
  end
  -- - Use `nested` to allow other events (useful for statuslines)
  api.nvim_create_autocmd('BufWriteCmd', { buffer = bufnr, nested = true, callback = finish })

  -- Define action to cancel confirm
  --- @type integer
  local cancel_au_id
  local function on_cancel(data)
    if tonumber(data.match) ~= win_id then
      return
    end
    pcall(api.nvim_del_autocmd, cancel_au_id)
    delete_buffer()
  end
  cancel_au_id = api.nvim_create_autocmd('WinClosed', { nested = true, callback = on_cancel })

  -- Set buffer-local options last (so that user autocmmands could override)
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = 'acwrite'
  vim.bo[bufnr].filetype = 'nvimpack'

  -- Attach in-process LSP for more capabilities
  vim.lsp.buf_attach_client(bufnr, require('vim.pack._lsp').client_id)
end

--- @param plug_list vim.pack.Plug[]
local function feedback_confirm(plug_list)
  -- TODO(echasnovski): Allow to not update all plugins via LSP code actions
  local function finish_update()
    local checkout_opts = { timestamp = get_timestamp(), skip_same_sha = true, silent = false }
    --- @async
    --- @param p vim.pack.Plug
    local function do_checkout(p)
      checkout(p, checkout_opts)
    end
    run_list(plug_list, do_checkout)

    feedback_log(plug_list)
  end

  -- Show report in new buffer in separate tabpage
  local lines = compute_feedback_lines(plug_list, false)
  show_confirm_buf(lines, finish_update)
end

--- @class vim.pack.keyset.update
--- @inlinedoc
--- @field force? boolean Whether to skip confirmation and make updates immediately. Default `false`.

--- Update plugins
---
--- - Download new changes from source.
--- - Infer update info (current/target state, changelog, etc.).
--- - Depending on `force`:
---     - If `false`, show confirmation buffer. It lists data about all set to
---       update plugins. Pending changes starting with `>` will be applied while
---       the ones starting with `<` will be reverted.
---       It has special in-process LSP server attached to provide more interactive
---       features. Currently supported methods:
---         - 'textDocument/documentSymbol' (`gO` via |lsp-defaults|
---           or |vim.lsp.buf.document_symbol()|) - show structure of the buffer.
---         - 'textDocument/hover' (`K` via |lsp-defaults| or |vim.lsp.buf.hover()|) -
---           show more information at cursor. Like details of particular pending
---           change or newer tag.
---
---       Execute |:write| to confirm update, execute |:quit| to discard the update.
---     - If `true`, make updates right away.
---
--- Notes:
--- - Every actual update is logged in "nvimpack.log" file inside "log" |stdpath()|.
---
--- @param names? string[] List of plugin names to update. Must be managed
--- by |vim.pack|, not necessarily already added in current session.
--- Default: names of all plugins added to current session via |vim.pack.add()|.
--- @param opts? vim.pack.keyset.update
function M.update(names, opts)
  vim.validate('names', names, vim.islist, true, 'list')
  opts = vim.tbl_extend('force', { force = false }, opts or {})

  local plug_list = plug_list_from_names(names)
  if #plug_list == 0 then
    notify('Nothing to update', 'WARN')
    return
  end
  git_ensure_exec()

  -- Perform update
  local checkout_opts = { timestamp = get_timestamp(), skip_same_sha = true, level = true }

  --- @async
  --- @param p vim.pack.Plug
  local function do_update(p)
    -- Fetch
    cli_async(git_cmd('fetch'), p.path)

    -- Compute change info: changelog if any, new tags if nothing to update
    infer_update_details(p)

    -- Checkout immediately if not need to confirm
    if opts.force then
      checkout(p, checkout_opts)
    end
  end
  local progress_title = opts.force and 'Updating' or 'Downloading updates'
  run_list(plug_list, do_update, progress_title)

  local feedback = opts.force and feedback_log or feedback_confirm
  feedback(plug_list)
end

--- Remove plugins from disk
---
--- @param names string[] List of plugin names to remove from disk. Must be managed
--- by |vim.pack|, not necessarily already added in current session.
function M.del(names)
  vim.validate('names', names, vim.islist, false, 'list')

  local plug_list = plug_list_from_names(names)
  if #plug_list == 0 then
    notify('Nothing to remove', 'WARN')
    return
  end

  for _, p in ipairs(plug_list) do
    trigger_event(p, 'PackDeletePre')

    vim.fs.rm(p.path, { recursive = true, force = true })
    added_plugins[p.path] = nil
    notify('Removed plugin `' .. p.spec.name .. '`', 'INFO')

    trigger_event(p, 'PackDelete')
  end
end

--- @inlinedoc
--- @class vim.pack.PlugData
--- @field spec vim.pack.SpecResolved A |vim.pack.Spec| with defaults made explicit.
--- @field path string Plugin's path on disk.
--- @field was_added boolean Whether plugin was added via |vim.pack.add()| in current session.

--- Get data about all plugins managed by |vim.pack|
--- @return vim.pack.PlugData[]
function M.get()
  -- Process added plugins in order they are added. Take into account that
  -- there might be "holes" after `vim.pack.del()`.
  --- @type table<integer,vim.pack.Plug>
  local added = {}
  for _, p_added in pairs(added_plugins) do
    added[p_added.id] = p_added.plug
  end

  --- @type vim.pack.PlugData[]
  local res = {}
  for i = 1, n_added_plugins do
    if added[i] ~= nil then
      res[#res + 1] = { spec = vim.deepcopy(added[i].spec), path = added[i].path, was_added = true }
    end
  end

  --- @async
  local function do_get()
    -- Process not added plugins
    local plug_dir = get_plug_dir()
    for n, t in vim.fs.dir(plug_dir, { depth = 1 }) do
      local path = vim.fs.joinpath(plug_dir, n)
      if t == 'directory' and not added_plugins[path] then
        local spec = { name = n, source = cli_async(git_cmd('get_origin'), path) }
        table.insert(res, { spec = spec, path = path, was_added = false })
      end
    end

    -- Make default `version` explicit
    for _, p_data in ipairs(res) do
      if p_data.spec.version == nil then
        p_data.spec.version = git_get_default_branch(p_data.path)
      end
    end
  end
  async.run(do_get):wait()

  return res
end

return M
