-- Render assistive reading on native CRe word geometry. No DOM/file changes,
-- navigation, secondary reader, or selection drawing are needed.
local Blitbuffer = require("ffi/blitbuffer")
local Renderer = {}

local function char_count(text)
    local _, count = text:gsub("[%z\1-\127\194-\244][\128-\191]*", "")
    return count
end

function Renderer.prefixLength(text)
    local length = char_count(text)
    return (length == 1 or length == 3) and 1 or math.ceil(length / 2)
end

local function clipped(box, width, height)
    local x = math.max(0, math.floor(box.x))
    local y = math.max(0, math.floor(box.y))
    local right = math.min(width, math.ceil(box.x + box.w))
    local bottom = math.min(height, math.ceil(box.y + box.h))
    if right > x and bottom > y then
        return { x = x, y = y, w = right - x, h = bottom - y }
    end
end

function Renderer.collect(doc, width, height, state)
    local result = { prefixes = {}, dots = {} }
    -- Explicitly suppress native selection drawing so dictionary/highlight
    -- state is untouched. Coordinates refer to the view just drawn by CRe.
    local range = doc:getTextFromPositions({ x = 0, y = 0 }, { x = width - 1, y = height - 1 }, true)
    if not range or not range.pos0 or not range.pos1 then
        return result
    end
    local start = range.pos0
    local previous_box
    local seen = {}
    -- Bound work even on malformed documents or broken engine traversal.
    for _ = 1, 4096 do
        if not start or seen[start] then
            break
        end
        seen[start] = true
        local order = doc:compareXPointers(start, range.pos1)
        if order == nil or order <= 0 then
            break
        end
        local ending = doc:getNextVisibleWordEnd(start)
        if not ending or ending == start then
            break
        end
        local text = doc:getTextFromXPointers(start, ending, false) or ""
        local boxes = doc:getScreenBoxesFromPositions(start, ending, true) or {}
        if state.bionic and text ~= "" then
            local middle = start
            for _ = 1, Renderer.prefixLength(text) do
                local next_char = doc:getNextVisibleChar(middle)
                if not next_char or next_char == middle then
                    break
                end
                middle = next_char
                if middle == ending then
                    break
                end
            end
            for _, box in ipairs(doc:getScreenBoxesFromPositions(start, middle, true) or {}) do
                local rect = clipped(box, width, height)
                if rect then
                    result.prefixes[#result.prefixes + 1] = rect
                end
            end
        end
        for _, box in ipairs(boxes) do
            local rect = clipped(box, width, height)
            if rect then
                if state.guided and previous_box then
                    local center = rect.y + rect.h / 2
                    local previous_center = previous_box.y + previous_box.h / 2
                    local left, right = previous_box.x + previous_box.w, rect.x
                    if rect.x < previous_box.x then
                        left, right = rect.x + rect.w, previous_box.x
                    end
                    local gap = right - left
                    -- Only a real gap on the same line; never across columns
                    -- or line wraps. Dot must fit without touching glyphs.
                    local radius = math.max(1, math.floor(math.min(rect.h, previous_box.h) / 18))
                    if
                        math.abs(center - previous_center) < math.min(rect.h, previous_box.h) / 3
                        and gap >= radius * 4
                        and gap <= rect.h * 1.5
                    then
                        result.dots[#result.dots + 1] = {
                            x = math.floor((left + right) / 2),
                            y = math.floor((center + previous_center) / 2),
                            r = radius,
                        }
                    end
                end
                previous_box = rect
            end
        end
        start = doc:getNextVisibleWordStart(ending)
    end
    return result
end

function Renderer.paint(doc, bb, x, y, area, state)
    if not state.bionic and not state.guided then
        return
    end
    local geometry = Renderer.collect(doc, area.w, area.h, state)
    if #geometry.prefixes > 0 then
        -- Take a pristine snapshot: shifted multiplication adds one pixel of
        -- weight while retaining the font, colors and exact native layout.
        -- Never modify the document's render buffer or a persistent cache.
        local source = Blitbuffer.new(area.w, area.h, bb:getType())
        source:blitFrom(bb, 0, 0, x, y, area.w, area.h)
        local ok, err = pcall(function()
            for _, box in ipairs(geometry.prefixes) do
                if box.w > 1 then
                    bb:blitFrom(source, x + box.x + 1, y + box.y, box.x, box.y, box.w - 1, box.h, bb.setPixelMultiply)
                end
            end
        end)
        source:free()
        if not ok then
            error(err)
        end
    end
    for _, dot in ipairs(geometry.dots) do
        bb:paintCircle(x + dot.x, y + dot.y, dot.r, Blitbuffer.COLOR_BLACK)
    end
end

return Renderer
