local t = require('luatest')
local fio = require('fio')
local treegen = require('luatest.treegen')
local justrun = require('luatest.justrun')

local g = t.group()

local appliers_script = [[
    local configdata = require('internal.config.configdata')
    local cluster_config = require('internal.config.cluster_config')
    local aboard = require('internal.config.utils.aboard')
    local cconfig = {
        credentials = {
            users = {
                guest = {
                    roles = {'super'},
                },
            },
        },
        memtx = {
            memory = 100000000,
        },
        fiber = {
            top = {
                enabled = true,
            },
            tx_user_pool_size = 123,
        },
        app = {
            file = 'script.lua',
        },
        groups = {
            ['group-001'] = {
                replicasets = {
                    ['replicaset-001'] = {
                        instances = {
                            ['instance-001'] = {},
                        },
                    },
                },
            },
        },
    }
    local iconfig = cluster_config:instantiate(cconfig, 'instance-001')
    config = {
        _configdata = configdata.new(iconfig, cconfig, 'instance-001'),
        _aboard = aboard.new(),
    }
    local mkdir = require('internal.config.applier.mkdir')
    mkdir.apply(config)
    local box_cfg = require('internal.config.applier.box_cfg')
    box_cfg.apply(config)
    local credentials = require('internal.config.applier.credentials')
    credentials.apply(config)
    local console = require('internal.config.applier.console')
    console.apply(config)
    local fiber = require('internal.config.applier.fiber')
    fiber.apply(config)
    local app = require('internal.config.applier.app').stage_2
    local ok, err = pcall(app.post_apply, config)
    %s
    os.exit(0)
]]

g.test_applier_mkdir = function()
    local dir = treegen.prepare_directory({}, {})
    local injection = [[
        print(config._configdata:get('wal.dir', {use_default = true}))
    ]]
    treegen.write_file(dir, 'main.lua', appliers_script:format(injection))

    local env = {}
    local opts = {nojson = true, stderr = false}
    local res = justrun.tarantool(dir, env, {'main.lua'}, opts)
    t.assert_equals(res.exit_code, 0)
    t.assert_equals(res.stdout, 'var/lib/instance-001')
    t.assert(fio.path.is_dir(fio.pathjoin(dir, '/var/lib/instance-001')))
end

g.test_applier_box_cfg = function()
    local dir = treegen.prepare_directory({}, {})
    local injection = [[
        print(box.cfg.memtx_memory)
    ]]
    treegen.write_file(dir, 'main.lua', appliers_script:format(injection))

    local env = {}
    local opts = {nojson = true, stderr = false}
    local res = justrun.tarantool(dir, env, {'main.lua'}, opts)
    t.assert_equals(res.exit_code, 0)
    t.assert_equals(res.stdout, '100000000')
end

g.test_applier_credentials = function()
    local dir = treegen.prepare_directory({}, {})
    local injection = [[
        local guest_id = box.space._user.index.name:get{'guest'}.id
        local super_id = box.space._user.index.name:get{'super'}.id
        print(box.space._priv:get{guest_id, 'role', super_id} ~= nil)
    ]]
    treegen.write_file(dir, 'main.lua', appliers_script:format(injection))

    local env = {}
    local opts = {nojson = true, stderr = false}
    local res = justrun.tarantool(dir, env, {'main.lua'}, opts)
    t.assert_equals(res.exit_code, 0)
    t.assert_equals(res.stdout, 'true')
end

g.test_applier_console = function()
    local dir = treegen.prepare_directory({}, {})
    local injection = [[
        local socket = require('socket')
        local data = config._configdata
        local path = data:get('console.socket', {use_default = true})
        local s = socket.tcp_connect('unix/', path)
        local greeting = s:read(128)
        local expr = '(%a+) %d.%d.%d (%(%a+ %a+%))'
        print(table.concat({greeting:gmatch(expr)()}, ' '))
    ]]
    treegen.write_file(dir, 'main.lua', appliers_script:format(injection))

    local env = {}
    local opts = {nojson = true, stderr = false}
    local res = justrun.tarantool(dir, env, {'main.lua'}, opts)
    t.assert_equals(res.exit_code, 0)
    t.assert_equals(res.stdout, 'Tarantool (Lua console)')
end

g.test_applier_fiber = function()
    local dir = treegen.prepare_directory({}, {})
    local injection = [[
        fiber = require('fiber')
        assert(fiber.top())
        assert(fiber.tx_user_pool_size() == 123)
    ]]
    treegen.write_file(dir, 'main.lua', appliers_script:format(injection))

    local env = {}
    local opts = {nojson = true, stderr = false}
    local res = justrun.tarantool(dir, env, {'main.lua'}, opts)
    t.assert_equals(res.exit_code, 0)
    t.assert_equals(res.stdout, '')
end

g.test_applier_app = function()
    local dir = treegen.prepare_directory({}, {})
    local injection = ''
    local app_script = 'print("something")'
    treegen.write_file(dir, 'main.lua', appliers_script:format(injection))
    treegen.write_file(dir, 'script.lua', app_script)

    local env = {}
    local opts = {nojson = true, stderr = false}
    local res = justrun.tarantool(dir, env, {'main.lua'}, opts)
    t.assert_equals(res.exit_code, 0)
    t.assert_equals(res.stdout, 'something')
end
