local T = require("tests.PanelsPlusTestFramework")
local H = require("tests.helper")
local Renderer = require("src.bionicrenderer")
local describe, it, check = T.describe, T.it, T.assert

describe("native reader integration", function()
    it("registers reader actions through the public dispatcher API", function()
        H.plugin()
        check.equals("ToggleBionicReading", H.actions.toggle_bionic_reading.event)
        check.is_true(H.actions.toggle_bionic_reading.rolling)
        check.equals("ToggleGuidedDots", H.actions.toggle_guided_dots.event)
    end)

    it("preserves the reader, document, checksum and statistics session across toggles", function()
        local p = H.plugin()
        local ui, doc, settings = p.ui, p.ui.document, p.ui.doc_settings
        local statistics = { id_curr_book = 17, start_current_period = 100, page_stat = { 31, 32 } }
        ui.statistics = statistics
        for _ = 1, 4 do
            p:onToggleBionicReading()
            p:onToggleGuidedDots()
        end
        check.equals(ui, p.ui)
        check.equals(doc, ui.document)
        check.equals(settings, ui.doc_settings)
        check.equals(statistics, ui.statistics)
        check.equals(17, statistics.id_curr_book)
        check.equals(100, statistics.start_current_period)
        check.equals(2, #statistics.page_stat)
        check.equals("original-book-md5", settings.values.partial_md5_checksum)
        check.equals("/books/example.epub", doc.file)
    end)

    it("persists both modes independently in the native book settings", function()
        local p = H.plugin()
        p:onToggleBionicReading()
        p:onToggleGuidedDots()
        p:onToggleBionicReading()
        local q = H.plugin()
        q:onReadSettings(p.ui.doc_settings)
        check.is_false(q.state.bionic)
        check.is_true(q.state.guided)
        local another_book = H.plugin()
        check.is_false(another_book.state.bionic)
        check.is_false(another_book.state.guided)
    end)

    it("draws emphasis after the native page with the native origin", function()
        local p = H.plugin()
        local original_paint = Renderer.paint
        local called, painted = 0, 0
        p:onCloseDocument()
        p.ui.view.drawPageView = function()
            called = called + 1
        end
        p:init()
        p:onToggleBionicReading()
        p.ui.view.state.offset = { x = 3, y = 4 }
        Renderer.paint = function(doc, _, x, y)
            check.equals(1, called)
            check.equals(p.ui.document, doc)
            check.equals(13, x)
            check.equals(24, y)
            painted = painted + 1
        end
        local ok, err = pcall(p.ui.view.drawPageView, p.ui.view, {}, 10, 20)
        Renderer.paint = original_paint
        if not ok then
            error(err)
        end
        check.equals(1, painted)
    end)

    it("uses the same rendering hook in scroll mode", function()
        local p = H.plugin()
        local old, count = Renderer.paint, 0
        Renderer.paint = function()
            count = count + 1
        end
        p:onToggleGuidedDots()
        local ok, err = pcall(p.ui.view.drawScrollView, p.ui.view, {}, 0, 0)
        Renderer.paint = old
        if not ok then
            error(err)
        end
        check.equals(1, count)
    end)

    it("does no extra rendering when both modes are disabled", function()
        local p = H.plugin()
        p.ui.view:drawPageView({}, 0, 0)
        p.ui.view:drawScrollView({}, 0, 0)
        check.is_false(p.state.bionic)
    end)

    it("exposes both mode checkboxes under typography", function()
        local p, menu = H.plugin(), {}
        p:addToMainMenu(menu)
        check.equals("typeset", menu.bionicreading.sorting_hint)
        local entries = menu.bionicreading.sub_item_table
        entries[1].callback()
        check.is_true(entries[1].checked_func())
        check.is_false(entries[2].checked_func())
    end)

    it("does not activate on PDF, comics, or the file manager", function()
        for _, doc in ipairs({ { info = { has_pages = true } }, { info = {} }, {} }) do
            local p = H.plugin(doc)
            local menu = {}
            p:addToMainMenu(menu)
            check.is_nil(menu.bionicreading)
            check.is_nil(p:onToggleBionicReading())
            check.is_nil(next(p.hooks))
        end
        local p = H.plugin()
        p.ui.document = nil
        check.is_false(p:isSupported())
    end)

    it("restores instance hooks on close without changing another reader", function()
        local p, q = H.plugin(), H.plugin()
        local q_hook = q.ui.view.drawPageView
        local original = p.hooks.drawPageView.original
        p:onCloseDocument()
        check.equals(original, p.ui.view.drawPageView)
        check.equals(q_hook, q.ui.view.drawPageView)
        check.is_nil(next(p.hooks))
    end)

    it("does not undo another plugin's later hook", function()
        local p = H.plugin()
        local later = function() end
        p.ui.view.drawPageView = later
        p:onCloseDocument()
        check.equals(later, p.ui.view.drawPageView)
    end)
end)
