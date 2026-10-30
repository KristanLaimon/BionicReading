local T = require("tests.PanelsPlusTestFramework")
local H = require("tests.helper")
local Renderer = require("src.bionicrenderer")
local describe, it, check = T.describe, T.it, T.assert

describe("native word geometry", function()
    it("retains the original author's one- and three-letter emphasis rule", function()
        for text, length in pairs({ a = 1, an = 1, the = 1, word = 2, hello = 3 }) do
            check.equals(length, Renderer.prefixLength(text))
        end
    end)

    it("counts Unicode characters rather than splitting UTF-8 bytes", function()
        check.equals(2, Renderer.prefixLength("café"))
        check.equals(3, Renderer.prefixLength("mañana"))
        check.equals(1, Renderer.prefixLength("漢字語"))
        check.equals(0, Renderer.prefixLength(""))
    end)

    it("collects real character-prefix boxes without drawing a selection", function()
        local geometry = Renderer.collect(H.document(), 600, 800, { bionic = true })
        check.equals(2, #geometry.prefixes)
        check.equals(24, geometry.prefixes[1].w)
        check.equals(10, geometry.prefixes[1].x)
        check.equals(0, #geometry.dots)
    end)

    it("places guided dots in whitespace between words", function()
        local geometry = Renderer.collect(H.document(), 600, 800, { guided = true })
        check.equals(0, #geometry.prefixes)
        check.equals(1, #geometry.dots)
        check.equals(54, geometry.dots[1].x)
        check.equals(20, geometry.dots[1].y)
    end)

    it("supports both modes at once", function()
        local geometry = Renderer.collect(H.document(), 600, 800, { bionic = true, guided = true })
        check.equals(2, #geometry.prefixes)
        check.equals(1, #geometry.dots)
    end)

    it("does not put dots across wrapped lines", function()
        local doc = H.document()
        local boxes = doc.getScreenBoxesFromPositions
        doc.getScreenBoxesFromPositions = function(self, start, ending)
            local result = boxes(self, start, ending)
            if start > 1 then
                result[1].y = 50
            end
            return result
        end
        check.equals(0, #Renderer.collect(doc, 600, 800, { guided = true }).dots)
    end)

    it("clips partially visible text and excludes offscreen text", function()
        local doc = H.document()
        doc.getScreenBoxesFromPositions = function(_, start)
            return { { x = -5, y = start == 1 and -5 or 900, w = 25, h = 20 } }
        end
        local geometry = Renderer.collect(doc, 600, 800, { bionic = true })
        check.equals(1, #geometry.prefixes)
        check.equals(0, geometry.prefixes[1].x)
        check.equals(0, geometry.prefixes[1].y)
        check.equals(20, geometry.prefixes[1].w)
        check.equals(15, geometry.prefixes[1].h)
    end)

    it("handles image-only pages without adding anything", function()
        local doc = H.document()
        doc.getTextFromPositions = function()
            return nil
        end
        local geometry = Renderer.collect(doc, 600, 800, { bionic = true, guided = true })
        check.equals(0, #geometry.prefixes)
        check.equals(0, #geometry.dots)
    end)

    it("stops a broken engine traversal rather than hanging", function()
        local doc = H.document()
        doc.getNextVisibleWordStart = function()
            return 1
        end
        local geometry = Renderer.collect(doc, 600, 800, { bionic = true })
        check.equals(1, #geometry.prefixes)
    end)

    it("releases the temporary page snapshot if painting fails", function()
        local BB = require("ffi/blitbuffer")
        local old_new, freed = BB.new, false
        BB.new = function()
            return {
                blitFrom = function() end,
                free = function()
                    freed = true
                end,
            }
        end
        local bb = {
            getType = function()
                return 1
            end,
            blitFrom = function()
                error("drawing failed")
            end,
        }
        local ok = pcall(Renderer.paint, H.document(), bb, 0, 0, { w = 600, h = 800 }, { bionic = true })
        BB.new = old_new
        check.is_false(ok)
        check.is_true(freed)
    end)
end)
