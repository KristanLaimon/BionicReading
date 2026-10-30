-- BionicReading: a fork of Gervie Macahia's Focus Reading patch.
-- Original concept and emphasis rule: Gervie Macahia.
-- Native-reader plugin and tests: KristanLaimon.
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Renderer = require("src.bionicrenderer")
local _ = require("gettext")

local BionicReading = WidgetContainer:extend({
    name = "bionicreading",
    is_doc_only = true,
})

function BionicReading:isSupported()
    local doc = self.ui.document
    return self.ui.rolling ~= nil
        and doc ~= nil
        and doc.info ~= nil
        and doc.info.has_pages == false
        and type(doc.getNextVisibleWordEnd) == "function"
        and type(doc.getScreenBoxesFromPositions) == "function"
end

function BionicReading:init()
    self.state = { bionic = false, guided = false }
    self.hooks = {}
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    if not self:isSupported() then
        return
    end

    -- Hook this reader instance only, immediately after the native page draw
    -- and before highlights, footer, and other native view decorations.
    local view = self.ui.view
    for _, method in ipairs({ "drawPageView", "drawScrollView" }) do
        local original = view[method]
        if original then
            local wrapper = function(this, bb, x, y)
                original(this, bb, x, y)
                if self.state.bionic or self.state.guided then
                    Renderer.paint(
                        self.ui.document,
                        bb,
                        x + this.state.offset.x,
                        y + this.state.offset.y,
                        this.visible_area,
                        self.state
                    )
                end
            end
            self.hooks[method] = { original = original, wrapper = wrapper }
            view[method] = wrapper
        end
    end
end

function BionicReading:onReadSettings(config)
    local saved = config:readSetting("bionicreading") or {}
    self.state = { bionic = saved.bionic == true, guided = saved.guided == true }
end

function BionicReading:onSaveSettings()
    self.ui.doc_settings:saveSetting("bionicreading", {
        bionic = self.state.bionic,
        guided = self.state.guided,
    })
end

function BionicReading:onDispatcherRegisterActions()
    Dispatcher:registerAction("toggle_bionic_reading", {
        category = "none",
        event = "ToggleBionicReading",
        title = _("Toggle bionic reading"),
        reader = true,
        rolling = true,
    })
    Dispatcher:registerAction("toggle_guided_dots", {
        category = "none",
        event = "ToggleGuidedDots",
        title = _("Toggle guided dots"),
        reader = true,
        rolling = true,
    })
end

function BionicReading:toggle(feature)
    if not self:isSupported() then
        return
    end
    self.state[feature] = not self.state[feature]
    self:onSaveSettings()
    UIManager:setDirty(self.ui.dialog, "ui")
    return true
end

function BionicReading:onToggleBionicReading()
    return self:toggle("bionic")
end

function BionicReading:onToggleGuidedDots()
    return self:toggle("guided")
end

function BionicReading:addToMainMenu(menu_items)
    if not self:isSupported() then
        return
    end
    menu_items.bionicreading = {
        text = _("Bionic reading"),
        sorting_hint = "typeset",
        sub_item_table = {
            {
                text = _("Bionic reading"),
                checked_func = function()
                    return self.state.bionic
                end,
                callback = function()
                    self:onToggleBionicReading()
                end,
            },
            {
                text = _("Guided dots"),
                checked_func = function()
                    return self.state.guided
                end,
                callback = function()
                    self:onToggleGuidedDots()
                end,
            },
        },
    }
end

function BionicReading:onCloseDocument()
    for method, hook in pairs(self.hooks) do
        if self.ui.view[method] == hook.wrapper then
            self.ui.view[method] = hook.original
        end
    end
    self.hooks = {}
end

return BionicReading
