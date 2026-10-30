local M = {}
M.actions = {}
M.dirty = 0
package.loaded.dispatcher = {
    registerAction = function(_, name, action)
        M.actions[name] = action
    end,
}
package.loaded["ui/uimanager"] = {
    setDirty = function()
        M.dirty = M.dirty + 1
    end,
}
package.loaded["ui/widget/container/widgetcontainer"] = {
    extend = function(_, class)
        return class
    end,
}
package.loaded.gettext = function(text)
    return text
end
if not package.loaded["ffi/blitbuffer"] then
    package.loaded["ffi/blitbuffer"] = { COLOR_BLACK = 0 }
end

function M.settings(values)
    return {
        values = values or {},
        readSetting = function(self, key)
            return self.values[key]
        end,
        saveSetting = function(self, key, value)
            self.values[key] = value
        end,
    }
end

function M.document(words)
    local doc = { info = { has_pages = false }, file = "/books/example.epub" }
    doc.words = words or { "Hello", "world" }
    local text = table.concat(doc.words, " ")
    local spans, position = {}, 1
    for _, word in ipairs(doc.words) do
        spans[#spans + 1] = { start = position, ending = position + #word }
        position = position + #word + 1
    end
    function doc:getTextFromPositions(_, _, no_selection)
        assert(no_selection == true)
        return { pos0 = 1, pos1 = #text + 1 }
    end
    function doc:compareXPointers(a, b)
        return a < b and 1 or (a == b and 0 or -1)
    end
    function doc:getNextVisibleWordEnd(start)
        for _, span in ipairs(spans) do
            if span.ending > start then
                return span.ending
            end
        end
    end
    function doc:getNextVisibleWordStart(ending)
        for _, span in ipairs(spans) do
            if span.start > ending then
                return span.start
            end
        end
    end
    function doc:getTextFromXPointers(start, ending, draw_selection)
        assert(draw_selection == false)
        return text:sub(start, ending - 1)
    end
    function doc:getNextVisibleChar(start)
        return start + 1
    end
    function doc:getScreenBoxesFromPositions(start, ending)
        return { { x = (start - 1) * 8 + 10, y = 10, w = (ending - start) * 8, h = 20 } }
    end
    return doc
end

function M.plugin(doc)
    local Plugin = require("main")
    local ui = {
        document = doc or M.document(),
        rolling = {},
        dialog = {},
        doc_settings = M.settings({ partial_md5_checksum = "original-book-md5" }),
        menu = { registerToMainMenu = function() end },
        view = {
            state = { offset = { x = 0, y = 0 } },
            visible_area = { w = 600, h = 800 },
            drawPageView = function() end,
            drawScrollView = function() end,
        },
        reloadDocument = function()
            error("must not reload the book")
        end,
        switchDocument = function()
            error("must not replace the reader")
        end,
        handleEvent = function()
            error("must not navigate or synthesize reader events")
        end,
    }
    local plugin = setmetatable({ ui = ui }, { __index = Plugin })
    plugin:init()
    plugin:onReadSettings(ui.doc_settings)
    return plugin
end

return M
