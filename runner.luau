--[[
  Runner — spec discovery + execution. Registration phase builds a tree
  of describe nodes (each with its own beforeAll/afterAll/beforeEach/afterEach
  hook lists + children + direct tests). Execution phase walks the tree
  depth-first, firing beforeAll/afterAll at describe boundaries, and
  beforeEach/afterEach around each test with outer→inner inheritance.

  This tree shape lets beforeAll/afterAll fire ONCE per describe scope; the
  earlier flat-tests[] model can't express that cleanly.

  beforeAll failure cascades to ALL descendant tests in the scope (direct +
  nested children). All sibling beforeAll hooks still run — one failure does
  not suppress the next — and every failure is collected in
  verdict.beforeAllErrors. afterAll always runs even on beforeAll failure.
]]

local Runner = {}

-- Module-level state, reset at the start of each runAll
local rootNode      -- the implicit top-level describe (no name, no hooks)
local stack         -- describe stack during registration
local currentFile = nil
local hasOnly = false
local warnings      -- registration-time warnings collected into verdict
local running = false  -- reentrancy guard for runAll
local runtimeWait    -- scheduler wait fn for yield-safe tests (set per runAll)
local defaultTimeout -- per-test timeout in seconds (set per runAll)

-- Single shared xpcall handler so the trace format is one source-of-truth
local function tracedError(e)
    return tostring(e) .. "\n--TRACE--\n" .. debug.traceback("", 2)
end

local function addWarning(msg)
    if warnings then table.insert(warnings, msg) end
end

local function newNode(name, opts)
    opts = opts or {}
    return {
        name = name,
        file = currentFile,
        beforeAll = {}, afterAll = {},
        beforeEach = {}, afterEach = {},
        children = {}, tests = {},
        skip = opts.skip or false,
        only = opts.only or false,
    }
end

-- ----------------------------------------------------------------------------
-- Row-shape classification for it.each / describe.each.
-- ----------------------------------------------------------------------------
local function classifyRow(row)
    -- Returns "array", "dict", "mixed", or "empty".
    local hasNumeric = rawget(row, 1) ~= nil
    local hasStringKey = false
    for k in pairs(row) do
        if type(k) == "string" then hasStringKey = true; break end
    end
    if hasNumeric and hasStringKey then return "mixed" end
    if hasNumeric then return "array" end
    if next(row) == nil then return "empty" end
    return "dict"
end

-- ----------------------------------------------------------------------------
-- Registration
-- ----------------------------------------------------------------------------
local function _describe(name, fn, opts)
    opts = opts or {}
    local node = newNode(name, opts)
    if node.only then hasOnly = true end

    local parent = stack[#stack]
    table.insert(parent.children, node)
    table.insert(stack, node)
    local ok, err = pcall(fn)
    table.remove(stack)

    if not ok then
        -- Poison the node atomically: any partial state from a half-completed
        -- registration is replaced with a single error placeholder. Avoids
        -- running half-registered hooks against a broken describe.
        node.children = {}
        node.beforeAll = {}
        node.afterAll = {}
        node.beforeEach = {}
        node.afterEach = {}
        node.tests = {{
            name = "(describe '" .. name .. "' errored during registration)",
            fn = function() error(err, 0) end,
            skip = false, only = false,
        }}
    end
end

local function _it(name, fn, opts)
    opts = opts or {}
    local parent = stack[#stack]
    if opts.only then hasOnly = true end
    table.insert(parent.tests, {
        name = name,
        fn = fn,
        skip = opts.skip or false,
        only = opts.only or false,
        timeout = opts.timeout,
    })
end

-- eachBind — shared helper for it.each / describe.each.
-- `register` is _it or _describe; receives (name, fn, opts).
local function eachBind(rows, register)
    -- Single pass: detect + validate row shapes.
    local kind  -- "array" or "dict" once any row is seen
    for i, row in ipairs(rows) do
        if type(row) ~= "table" then
            error("each: row " .. i .. " is " .. type(row) .. ", expected table", 3)
        end
        local rowKind = classifyRow(row)
        if rowKind == "mixed" then
            error(
                ("each: row %d has both numerical and string keys — pick one shape (array OR dict)"):format(i),
                3
            )
        end
        if rowKind == "empty" then rowKind = "array" end  -- empty defaults to array
        if kind == nil then
            kind = rowKind
        elseif rowKind ~= kind then
            error(
                ("each: rows must all be arrays or all be dicts; row %d is %s, row 1 is %s"):format(
                    i, rowKind, kind
                ), 3
            )
        end
    end
    local isArray = kind ~= "dict"  -- nil (no rows) and "array" both go this way
    local pattern = isArray and "%$(%d+)" or "%$(%w+)"

    local function bind(nameFmt, fn, opts)
        for _, row in ipairs(rows) do
            local missingTokens
            local name = (nameFmt:gsub(pattern, function(token)
                local key = isArray and tonumber(token) or token
                local v = row[key]
                if v == nil then
                    missingTokens = missingTokens or {}
                    table.insert(missingTokens, "$" .. token)
                    return ""  -- per spec: substitute empty string
                end
                return tostring(v)
            end))
            if missingTokens then
                addWarning(("it.each: name template '%s' has no value for %s in a row"):format(
                    nameFmt, table.concat(missingTokens, ", ")
                ))
            end
            if isArray then
                -- table.unpack(row) alone stops at #row, which is undefined
                -- for rows with nil holes like { "a", nil, "c" } — exactly the
                -- rows people write to test nil handling. Unpack to the
                -- highest numeric key so arity survives.
                local arity = 0
                for k in pairs(row) do
                    if type(k) == "number" and k > arity then arity = k end
                end
                register(name, function() return fn(table.unpack(row, 1, arity)) end, opts)
            else
                register(name, function() return fn(row) end, opts)
            end
        end
    end

    return setmetatable({
        skip = function(nameFmt, fn, userOpts)
            bind(nameFmt, fn, { skip = true, timeout = userOpts and userOpts.timeout })
        end,
        only = function(nameFmt, fn, userOpts)
            bind(nameFmt, fn, { only = true, timeout = userOpts and userOpts.timeout })
        end,
    }, {
        __call = function(_, nameFmt, fn, userOpts)
            bind(nameFmt, fn, { timeout = userOpts and userOpts.timeout })
        end,
    })
end

-- Bind .each helpers BEFORE Runner.describe/Runner.it construction so the
-- forward-reference workaround isn't needed.
local function itEach(rows) return eachBind(rows, _it) end
local function describeEach(rows) return eachBind(rows, _describe) end

Runner.describe = setmetatable({
    skip = function(name, fn) _describe(name, fn, { skip = true }) end,
    only = function(name, fn) _describe(name, fn, { only = true }) end,
    each = describeEach,
}, {
    __call = function(_, name, fn) _describe(name, fn) end,
})

Runner.it = setmetatable({
    skip = function(name, fn, userOpts)
        _it(name, fn, { skip = true, timeout = userOpts and userOpts.timeout })
    end,
    only = function(name, fn, userOpts)
        _it(name, fn, { only = true, timeout = userOpts and userOpts.timeout })
    end,
    each = itEach,
}, {
    __call = function(_, name, fn, userOpts)
        _it(name, fn, { timeout = userOpts and userOpts.timeout })
    end,
})

-- ----------------------------------------------------------------------------
-- Hooks. Top-level calls (outside any describe) are rejected loudly so
-- file-level hooks don't leak across spec files (rootNode is shared).
-- ----------------------------------------------------------------------------
local function topLevelGuard(hookName)
    error(hookName .. " must be called inside a describe() block — top-level hooks leak across spec files", 3)
end

function Runner.beforeAll(fn)
    if #stack <= 1 then topLevelGuard("beforeAll") end
    table.insert(stack[#stack].beforeAll, fn)
end

function Runner.afterAll(fn)
    if #stack <= 1 then topLevelGuard("afterAll") end
    table.insert(stack[#stack].afterAll, fn)
end

function Runner.beforeEach(fn)
    if #stack <= 1 then topLevelGuard("beforeEach") end
    table.insert(stack[#stack].beforeEach, fn)
end

function Runner.afterEach(fn)
    if #stack <= 1 then topLevelGuard("afterEach") end
    table.insert(stack[#stack].afterEach, fn)
end

-- ----------------------------------------------------------------------------
-- Discovery
-- ----------------------------------------------------------------------------
local function registerErrorPlaceholder(name, errMsg)
    table.insert(rootNode.tests, {
        name = name,
        fn = function() error(errMsg, 0) end,
        skip = false, only = false,
    })
end

local function collectSpecs(root)
    -- Portable form: a plain array of { name = string, fn = function } entries.
    -- Used outside Roblox (e.g. Lune), where there is no Instance tree to walk.
    if type(root) == "table" then
        for i, entry in ipairs(root) do
            if type(entry) ~= "table" or type(entry.name) ~= "string" or type(entry.fn) ~= "function" then
                registerErrorPlaceholder(
                    ("(invalid spec entry #%d)"):format(i),
                    "expected { name = string, fn = function }"
                )
            else
                currentFile = entry.name
                local okRun, errRun = pcall(entry.fn)
                if not okRun then
                    registerErrorPlaceholder("(spec registration failed) " .. entry.name, errRun)
                end
            end
        end
        currentFile = nil
        return
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("ModuleScript") and descendant.Name:sub(-5) == ".spec" then
            currentFile = descendant:GetFullName()
            local okReq, modOrErr = pcall(require, descendant)
            if not okReq then
                registerErrorPlaceholder("(spec require failed) " .. descendant.Name, modOrErr)
            elseif type(modOrErr) ~= "function" then
                registerErrorPlaceholder(
                    "(spec did not return function) " .. descendant.Name,
                    "spec module must return a function; got " .. type(modOrErr)
                )
            else
                local okRun, errRun = pcall(modOrErr)
                if not okRun then
                    registerErrorPlaceholder("(spec registration failed) " .. descendant.Name, errRun)
                end
            end
        end
    end
    currentFile = nil
end

-- ----------------------------------------------------------------------------
-- Execution — tree walk.
-- beforeAll failure cascades to ALL descendant tests via the ancestorBeforeAllFailed
-- argument. Every beforeAll error is collected in counters.beforeAllErrors;
-- the FIRST error in a scope is propagated to descendant tests' failure messages.
-- ----------------------------------------------------------------------------
-- Runs one test body (hooks included) yield-safely. The body executes inside
-- a coroutine wrapped in xpcall, so errors thrown after a yield are still
-- captured here instead of escaping to the runtime's scheduler. Returns
-- (true) on pass or (false, errorString) on failure. Exposed as _runTestFn
-- for the framework's own spec suite.
local function runTestFn(fn, timeoutSec, waitFn)
    local done = false
    local failErr = nil
    local co = coroutine.create(function()
        local ok, err = xpcall(fn, tracedError)
        if not ok then failErr = tostring(err) end
        done = true
    end)

    local resumeOk, resumeErr = coroutine.resume(co)
    if not resumeOk then
        return false, tostring(resumeErr)
    end
    if done then
        return failErr == nil, failErr
    end

    -- The body yielded. From here on only a scheduler can finish it.
    if not waitFn then
        coroutine.close(co)
        return false, "test yielded but no scheduler is available; pass opts.wait to runAll or run inside Roblox"
    end
    local elapsed = 0
    while not done and elapsed < timeoutSec do
        elapsed = elapsed + (waitFn(0.03) or 0.03)
    end
    if not done then
        coroutine.close(co)
        return false, string.format("timed out after %.1fs", timeoutSec)
    end
    return failErr == nil, failErr
end

-- Runs one test: the beforeEach chain and the body execute protected
-- together, then ALL afterEach hooks run regardless of the body's outcome
-- (Jest semantics; a timed-out or failed test must not skip cleanup). Each
-- afterEach is protected individually so one failing cleanup doesn't skip
-- its siblings, and afterEach failures fail the test without masking the
-- body's own error. Exposed as _runTestWithHooks for the framework's specs.
local function runTestWithHooks(beforeFns, testFn, afterFns, timeoutSec, waitFn)
    local ok, err = runTestFn(function()
        for _, fn in ipairs(beforeFns) do fn() end
        testFn()
    end, timeoutSec, waitFn)

    local afterErrs = {}
    local afterRunOk, afterRunErr = runTestFn(function()
        for _, fn in ipairs(afterFns) do
            local aOk, aErr = xpcall(fn, tracedError)
            if not aOk then table.insert(afterErrs, tostring(aErr)) end
        end
    end, timeoutSec, waitFn)
    if not afterRunOk then
        -- The afterEach composite itself yielded into a timeout or had no
        -- scheduler; surface that like any other cleanup failure.
        table.insert(afterErrs, tostring(afterRunErr))
    end

    if ok and #afterErrs == 0 then return true end
    local parts = {}
    if not ok then table.insert(parts, tostring(err)) end
    for _, e in ipairs(afterErrs) do table.insert(parts, "afterEach failed: " .. e) end
    return false, table.concat(parts, "\n")
end

local function visitNode(node, parentBefore, parentAfter, ancestorSkip, ancestorOnly, ancestorBeforeAllFailed, ancestorBeforeAllError, pathSegs, counters)
    local effectiveSkip = ancestorSkip or node.skip
    local effectiveOnly = ancestorOnly or node.only

    -- Build inherited hook lists
    local nodeBefore = {}
    for _, fn in ipairs(parentBefore) do table.insert(nodeBefore, fn) end
    for _, fn in ipairs(node.beforeEach) do table.insert(nodeBefore, fn) end

    local nodeAfter = {}
    for _, fn in ipairs(node.afterEach) do table.insert(nodeAfter, fn) end
    for _, fn in ipairs(parentAfter) do table.insert(nodeAfter, fn) end

    -- Push name onto path
    local thisPath = {}
    for _, p in ipairs(pathSegs) do table.insert(thisPath, p) end
    if node.name then table.insert(thisPath, node.name) end

    -- Run beforeAll hooks. All siblings run even after one fails.
    -- Inherited (ancestor) failure already short-circuits us into failed-mode,
    -- but we still run this node's own beforeAll siblings for visibility into
    -- whether they would have failed too.
    local beforeAllFailed = ancestorBeforeAllFailed or false
    local beforeAllError = ancestorBeforeAllError
    if not effectiveSkip then
        for _, fn in ipairs(node.beforeAll) do
            local ok, err = xpcall(fn, tracedError)
            if not ok then
                local errStr = tostring(err)
                table.insert(counters.beforeAllErrors, {
                    path = table.concat(thisPath, " > "),
                    error = errStr,
                })
                if not beforeAllFailed then
                    -- First failure in this scope is what descendant tests see.
                    beforeAllFailed = true
                    beforeAllError = errStr
                end
            end
        end
    end

    -- Run direct tests of this node
    for _, test in ipairs(node.tests) do
        local pathStr
        if #thisPath == 0 then
            pathStr = test.name  -- root-level placeholder (from collectSpecs failure paths)
        else
            pathStr = table.concat(thisPath, " > ") .. " > " .. test.name
        end

        local shouldRun
        if hasOnly then
            shouldRun = (effectiveOnly or test.only) and not (effectiveSkip or test.skip)
        else
            shouldRun = not (effectiveSkip or test.skip)
        end

        counters.totalTests = counters.totalTests + 1
        if not shouldRun then
            counters.skipped = counters.skipped + 1
        elseif beforeAllFailed then
            counters.failed = counters.failed + 1
            table.insert(counters.failures, {
                path = pathStr,
                file = node.file,
                error = "beforeAll failed: " .. beforeAllError,
            })
        else
            local ok, err = runTestWithHooks(
                nodeBefore, test.fn, nodeAfter,
                test.timeout or defaultTimeout, runtimeWait)
            if ok then
                counters.passed = counters.passed + 1
            else
                counters.failed = counters.failed + 1
                table.insert(counters.failures, {
                    path = pathStr,
                    file = node.file,
                    error = tostring(err),
                })
            end
        end
    end

    -- Recurse into child describes. CRITICAL: pass beforeAllFailed/Error down
    -- so nested-describe tests ALSO get marked failed when outer beforeAll throws.
    for _, child in ipairs(node.children) do
        visitNode(child, nodeBefore, nodeAfter, effectiveSkip, effectiveOnly, beforeAllFailed, beforeAllError, thisPath, counters)
    end

    -- Run afterAll for this node (always runs, even if beforeAll failed)
    if not effectiveSkip then
        for _, fn in ipairs(node.afterAll) do
            local ok, err = xpcall(fn, tracedError)
            if not ok then
                table.insert(counters.afterAllErrors, {
                    path = table.concat(thisPath, " > "),
                    error = tostring(err),
                })
            end
        end
    end
end

-- Splits captured warning messages into expected (matched an allowlist
-- entry) and unexpected. Matching is PLAIN substring (find with plain=true),
-- not Lua patterns, so allowlist entries can contain % ( ) etc. verbatim.
-- Entries are strings or { pattern = string, reason = string } tables;
-- empty patterns are ignored rather than matching everything.
local function classifyWarnings(messages, expectedPatterns)
    local expected, unexpected = {}, {}
    for _, message in ipairs(messages) do
        local matched = false
        for _, entry in ipairs(expectedPatterns) do
            local pattern = type(entry) == "table" and entry.pattern or entry
            if type(pattern) == "string" and pattern ~= "" and string.find(message, pattern, 1, true) then
                matched = true
                break
            end
        end
        if matched then
            table.insert(expected, message)
        else
            table.insert(unexpected, message)
        end
    end
    return expected, unexpected
end

-- Captures warn output for the duration of a run; returns an uninstall
-- function. Inside Roblox the source is LogService.MessageOut, which also
-- catches engine warnings (bad asset ids, deprecations). Outside Roblox the
-- framework cannot self-install a capture: a warn override assigned from
-- this module is invisible to spec code (Roblox scripts have per-script
-- globals; Lune isolates module global WRITES even though reads inherit).
-- Entry scripts install their own entry-level warn override and hand the
-- buffer to runAll via opts.capturedWarnings; see Tests/RunInLune.luau.
local function installWarningCapture(buffer)
    if type(game) == "userdata" then
        local okSvc, LogService = pcall(function() return game:GetService("LogService") end)
        if okSvc and LogService then
            local conn = LogService.MessageOut:Connect(function(message, messageType)
                if messageType == Enum.MessageType.MessageWarning then
                    table.insert(buffer, message)
                end
            end)
            return function()
                -- Let queued MessageOut signals deliver. Two frames is a
                -- heuristic, not a guarantee; a warning emitted in the very
                -- last frame can still escape (documented in debugging.md).
                if runtimeWait then
                    runtimeWait()
                    runtimeWait()
                end
                conn:Disconnect()
            end
        end
    end
    return function() end
end

function Runner.runAll(specRoot, opts)
    -- Reentrancy guard: detect recursive runAll (would corrupt module state).
    assert(not running, "Runner.runAll is not reentrant — a suite is already running")

    opts = opts or {}
    runtimeWait = opts.wait
        or (type(task) == "table" and type(task.wait) == "function" and task.wait)
        or nil
    defaultTimeout = opts.timeout or 5

    -- opts.capturedWarnings is an externally-filled sink (entry-level warn
    -- override) merged with whatever the framework can capture itself.
    local capturedWarnings = opts.capturedWarnings or {}
    local uninstallCapture = installWarningCapture(capturedWarnings)

    rootNode = newNode(nil)
    stack = { rootNode }
    hasOnly = false
    currentFile = nil
    warnings = {}

    -- Set the guard as late as possible: an error in the setup above would
    -- otherwise leave running=true forever and wedge every future runAll.
    running = true

    local ok, result = pcall(function()
        collectSpecs(specRoot)

        local startTime = os.clock()
        local counters = {
            passed = 0, failed = 0, skipped = 0, totalTests = 0,
            failures = {},
            beforeAllErrors = {},
            afterAllErrors = {},
        }

        visitNode(rootNode, {}, {}, false, false, false, nil, {}, counters)

        return {
            ok = counters.failed == 0,
            passed = counters.passed,
            failed = counters.failed,
            skipped = counters.skipped,
            totalTests = counters.totalTests,
            durationSec = os.clock() - startTime,
            failures = counters.failures,
            beforeAllErrors = counters.beforeAllErrors,
            afterAllErrors = counters.afterAllErrors,
            warnings = warnings,
        }
    end)

    uninstallCapture()  -- needs runtimeWait still set for the Roblox flush
    running = false  -- always release the guard
    runtimeWait = nil
    warnings = nil
    if not ok then error(result, 0) end

    -- Warning gate. Registration-time warnings (result.warnings) stay a
    -- separate channel; the gate covers runtime warn output only.
    local expectedList, unexpectedList = classifyWarnings(capturedWarnings, opts.expectedWarnings or {})
    result.capturedWarnings = capturedWarnings
    result.expectedWarnings = expectedList
    result.unexpectedWarnings = unexpectedList
    result.warningsClean = #unexpectedList == 0
    if opts.strictWarnings and not result.warningsClean then
        result.ok = false
        table.insert(result.failures, {
            path = "(warning gate)",
            file = nil,
            error = string.format("%d unexpected warning(s):\n%s",
                #unexpectedList, table.concat(unexpectedList, "\n")),
        })
    end
    return result
end


-- Test seams only; not part of the public API surface re-exported by Start.
Runner._runTestFn = runTestFn
Runner._runTestWithHooks = runTestWithHooks
Runner._classifyWarnings = classifyWarnings

return Runner
