-- Optional host integration tests against the installed KOReader CRe/BB libs.
-- No display, network, user books, settings, or statistics database are opened.
local pipe = assert(io.popen("pwd", "r"))
local repo = pipe:read("*l")
pipe:close()
local installed = os.getenv("KOREADER_DIR") or "/usr/lib/koreader"
package.path = repo
    .. "/?.lua;"
    .. repo
    .. "/?/init.lua;"
    .. installed
    .. "/?.lua;"
    .. installed
    .. "/frontend/?.lua;"
    .. installed
    .. "/common/?.lua;"
    .. package.path
package.cpath = installed .. "/?.so;" .. package.cpath
local lfs = require("libs/libkoreader-lfs")
assert(lfs.chdir(installed))
require("ffi/loadlib")
local cre = require("libs/libkoreader-cre")
local BB = require("ffi/blitbuffer")
local Renderer = require("src.bionicrenderer")
local T = require("tests.PanelsPlusTestFramework")
local check = T.assert

local output = os.tmpname()
os.remove(output)
assert(lfs.mkdir(output))
cre.initCache(output .. "/cache", 1024 * 1024)
cre.registerFont(installed .. "/fonts/noto/NotoSerif-Regular.ttf")
local path = output .. "/book.html"
local content = "<html><body><h1>Native reading</h1><p>Hello wonderful world. café mañana words!</p>"
    .. string.rep(
        "<p>Reading remains in the same native book. A dictionary selection still sees complete words.</p>",
        45
    )
    .. "</body></html>"
local file = assert(io.open(path, "wb"))
file:write(content)
file:close()
local engine = cre.newDocView(600, 800, 1)
engine:readDefaults()
engine:setFontFace("Noto Serif")
engine:setFontSize(28)
assert(engine:loadDocument(path))
engine:renderDocument()
local doc = { file = path, info = { has_pages = false } }
function doc:getTextFromPositions(a, b, no_selection)
    assert(no_selection)
    return engine:getTextFromPositions(a.x, a.y, b.x, b.y, false, false)
end
function doc:getScreenBoxesFromPositions(a, b, segments)
    local result = {}
    for _, box in ipairs(engine:getWordBoxesFromPositions(a, b, segments) or {}) do
        result[#result + 1] = { x = box.x0, y = box.y0, w = box.x1 - box.x0, h = box.y1 - box.y0 }
    end
    return result
end
function doc:getTextFromXPointers(a, b, selection)
    assert(selection == false)
    return engine:getTextFromXPointers(a, b, false, false)
end
for _, name in ipairs({ "compareXPointers", "getNextVisibleChar", "getNextVisibleWordEnd", "getNextVisibleWordStart" }) do
    doc[name] = function(_, ...)
        return engine[name](engine, ...)
    end
end
local area = { w = 600, h = 800 }
local function render(state, name)
    local bb = BB.new(area.w, area.h, BB.TYPE_BB8)
    engine:drawCurrentPage(bb)
    Renderer.paint(doc, bb, 0, 0, area, state)
    if name then
        bb:writePNG(output .. "/" .. name .. ".png")
    end
    return bb
end
local function difference(a, b)
    local count = 0
    for y = 0, area.h - 1 do
        for x = 0, area.w - 1 do
            if a:getPixel(x, y):getColor8().a ~= b:getPixel(x, y):getColor8().a then
                count = count + 1
            end
        end
    end
    return count
end

T.describe("installed KOReader native rendering", function()
    T.it("emphasizes word prefixes and adds dots on a real rendered page", function()
        local before = render({}, "before")
        local after = render({ bionic = true, guided = true }, "both")
        local geometry = Renderer.collect(doc, area.w, area.h, { bionic = true, guided = true })
        check.is_true(#geometry.prefixes > 30)
        check.is_true(#geometry.dots > 20)
        check.is_true(difference(before, after) > 100)
        print(string.format("    %d prefixes, %d dots", #geometry.prefixes, #geometry.dots))
        before:free()
        after:free()
    end)

    T.it("restores the exact native pixels when disabled", function()
        local before = render({})
        local enabled = render({ bionic = true })
        local disabled = render({})
        check.equals(0, difference(before, disabled))
        before:free()
        enabled:free()
        disabled:free()
    end)

    T.it("retains file bytes, pagination, XPointer, and complete dictionary text", function()
        local xp, pages = engine:getXPointer(), engine:getPages()
        local a = doc:getTextFromPositions({ x = 0, y = 0 }, { x = 599, y = 799 }, true)
        local before = doc:getTextFromXPointers(a.pos0, a.pos1, false)
        for _, state in ipairs({ { bionic = true }, { guided = true }, { bionic = true, guided = true }, {} }) do
            render(state):free()
        end
        check.equals(xp, engine:getXPointer())
        check.equals(pages, engine:getPages())
        check.equals(before, doc:getTextFromXPointers(a.pos0, a.pos1, false))
        local input = assert(io.open(path, "rb"))
        check.equals(content, input:read("*a"))
        input:close()
    end)

    T.it("renders another page and scroll mode without changing position", function()
        engine:gotoPage(2)
        local page = engine:getCurrentPage()
        render({ bionic = true, guided = true }, "page2"):free()
        check.equals(page, engine:getCurrentPage())
        engine:setViewMode(0)
        engine:renderDocument()
        engine:gotoPos(125)
        local pos = engine:getCurrentPos()
        render({ bionic = true, guided = true }, "scroll"):free()
        check.equals(pos, engine:getCurrentPos())
    end)

    T.it("toggles the plugin on a real document without replacing its statistics session", function()
        local H = require("tests.helper")
        local p = H.plugin(doc)
        local statistics = { doc_md5 = "unchanged", id_curr_book = 42, page_stat = {} }
        p.ui.statistics = statistics
        p.ui.view.drawPageView = p.hooks.drawPageView.wrapper
        local bb = BB.new(600, 800, BB.TYPE_BB8)
        engine:drawCurrentPage(bb)
        for _ = 1, 2 do
            p:onToggleBionicReading()
            p:onToggleGuidedDots()
            p.ui.view:drawPageView(bb, 0, 0)
            check.equals(doc, p.ui.document)
            check.equals(statistics, p.ui.statistics)
            check.equals(42, statistics.id_curr_book)
            check.equals("original-book-md5", p.ui.doc_settings.values.partial_md5_checksum)
        end
        p:onCloseDocument()
        bb:free()
    end)

    T.it("collects both columns of a native two-page view", function()
        engine:setViewMode(1)
        engine:setVisiblePageCount(2)
        engine:renderDocument()
        engine:gotoPage(1)
        local bb = render({ bionic = true, guided = true }, "columns")
        local geometry = Renderer.collect(doc, 600, 800, { bionic = true })
        local left, right = 0, 0
        for _, box in ipairs(geometry.prefixes) do
            if box.x < 300 then
                left = left + 1
            else
                right = right + 1
            end
        end
        bb:free()
        check.is_true(left > 10)
        check.is_true(right > 10)
    end)

    T.it("saves reading time and pages through KOReader's real statistics plugin and SQLite", function()
        -- Stub only unrelated UI services. Statistics code, schema, page-time
        -- accounting, insertion, SQL view, and SQLite library are the real ones.
        local H = require("tests.helper")
        for _, module in ipairs({
            "ui/bidi",
            "ui/widget/buttondialog",
            "ui/widget/confirmbox",
            "docsettings",
            "ui/widget/infomessage",
            "ui/widget/keyvaluepage",
            "readerprogress",
            "readhistory",
            "datetime",
        }) do
            package.loaded[module] = {}
        end
        package.loaded.datastorage = {
            getDataDir = function()
                return output
            end,
            getSettingsDir = function()
                return output
            end,
        }
        package.loaded.device = {
            canUseWAL = function()
                return false
            end,
        }
        package.loaded.optmath = math
        package.loaded["ui/widget/widget"] = package.loaded["ui/widget/container/widgetcontainer"]
        package.loaded.logger = { dbg = function() end, info = function() end }
        package.loaded.gettext = setmetatable({
            pgettext = function(_, text)
                return text
            end,
            ngettext = function(text)
                return text
            end,
        }, {
            __call = function(_, text)
                return text
            end,
        })
        local Statistics = dofile(installed .. "/plugins/statistics.koplugin/main.lua")
        local SQ3 = require("lua-ljsqlite3/init")
        local p = H.plugin(doc)
        local stats = setmetatable({
            ui = p.ui,
            document = doc,
            is_doc_not_frozen = true,
            settings = { is_enabled = true, min_sec = 5, max_sec = 120 },
            doc_md5 = p.ui.doc_settings.values.partial_md5_checksum,
            data = {
                title = "Native reading",
                authors = "Test",
                notes = 0,
                highlights = 0,
                pages = engine:getPages(),
                series = "N/A",
                language = "en",
            },
            curr_page = 1,
            book_read_pages = 0,
            book_read_time = 0,
        }, { __index = Statistics })
        p.ui.statistics = stats
        local conn = SQ3.open(output .. "/statistics.sqlite3")
        stats:createDB(conn)
        conn:close()
        local real_time, now = os.time, 1800000000
        os.time = function() -- luacheck: ignore 122
            return now
        end
        local ok, err = pcall(function()
            stats.id_curr_book = stats:getIdBookDB()
            local id = stats.id_curr_book
            stats:resetVolatileStats(now)
            p:onToggleBionicReading()
            now = now + 15
            stats:onPageUpdate(2)
            p:onToggleGuidedDots()
            now = now + 12
            p:onToggleBionicReading()
            stats:onCloseDocument()
            check.equals(id, stats:getIdBookDB())
            check.equals(27, stats.book_read_time)
            check.equals(2, stats.book_read_pages)
            local database = SQ3.open(output .. "/statistics.sqlite3")
            check.equals(1, tonumber(database:rowexec("SELECT count(*) FROM book;")))
            check.equals(27, tonumber(database:rowexec("SELECT total_read_time FROM book;")))
            check.equals(2, tonumber(database:rowexec("SELECT total_read_pages FROM book;")))
            check.equals("original-book-md5", database:rowexec("SELECT md5 FROM book;"))
            database:close()
        end)
        os.time = real_time -- luacheck: ignore 122
        p:onCloseDocument()
        if not ok then
            error(err)
        end
    end)

    T.it("renders an EPUB without changing its bytes, page count or position", function()
        engine:close()
        engine = cre.newDocView(600, 800, 1)
        engine:readDefaults()
        engine:setFontFace("Noto Serif")
        engine:setFontSize(28)
        doc.file = repo .. "/tests/fixtures/book.epub"
        local input = assert(io.open(doc.file, "rb"))
        local before = input:read("*a")
        input:close()
        assert(engine:loadDocument(doc.file))
        engine:renderDocument()
        engine:gotoPage(2)
        local pages, xp = engine:getPages(), engine:getXPointer()
        render({ bionic = true, guided = true }, "epub"):free()
        check.is_true(#Renderer.collect(doc, 600, 800, { bionic = true }).prefixes > 20)
        check.equals(pages, engine:getPages())
        check.equals(xp, engine:getXPointer())
        input = assert(io.open(doc.file, "rb"))
        check.equals(before, input:read("*a"))
        input:close()
    end)
end)
engine:close()
print("Native rendering artifacts: " .. output)
os.exit(T.summary() and 0 or 1)
