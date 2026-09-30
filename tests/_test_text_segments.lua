-- tests/_test_text_segments.lua
-- Pure-Lua unit tests for bookshelf_text_segments.lua.

package.path = "./?.lua;./?/init.lua;" .. package.path

-- The module requires ffi/utf8proc + util at load, but only its uppercase
-- helper uses them; the segmentation the tests exercise (labelSegments ->
-- decodeAt / isIconCodepoint) is pure UTF-8 byte decoding. Stub the two so the
-- suite runs standalone instead of being skipped.
package.loaded["ffi/utf8proc"] = { uppercase_dumb = function(s) return s end }
package.loaded["util"] = { fixUtf8 = function(s) return s end }

local Segments = dofile("lib/bookshelf_text_segments.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        pass = pass + 1
    else
        fail = fail + 1
        io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n")
    end
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "") .. " expected=" .. tostring(expected) .. " got=" .. tostring(actual), 2)
    end
end

local function classes(label)
    local out = {}
    for _, seg in ipairs(Segments.labelSegments(label)) do
        out[#out + 1] = seg.class .. ":" .. seg.text
    end
    return table.concat(out, "|")
end

test("latin-1 letters stay text", function()
    eq(classes("Drömräkning"), "text:Drömräkning")
    eq(classes("ÅÄÖ åäö"), "text:ÅÄÖ åäö")
end)

test("non-latin titles stay text", function()
    eq(classes("進撃の巨人"), "text:進撃の巨人")
end)

test("private-use nerd font glyphs are icons", function()
    eq(classes("Manga \239\128\130"), "text:Manga |icon:\239\128\130")
end)

test("emoji and dingbats are icons", function()
    eq(classes("Done ✓"), "text:Done |icon:✓")
    eq(classes("Smile 😀"), "text:Smile |icon:😀")
end)

-- SVG/PNG icons in a shelf label (GitHub issue 469): an [icon=NAME] token,
-- as the icon picker inserts it and Bookends writes it, is its own segment.
test("an [icon=NAME] token is an image segment carrying its name", function()
    local segs = Segments.labelSegments("[icon=my cat] Books")
    eq(#segs, 2)
    eq(segs[1].class, "image"); eq(segs[1].name, "my cat")
    eq(segs[2].class, "text"); eq(segs[2].text, " Books")
    local mid = Segments.labelSegments("A[icon=x]B")
    eq(#mid, 3); eq(mid[2].class, "image"); eq(mid[3].text, "B")
end)

test("a bracket that is not an icon token stays text", function()
    local segs = Segments.labelSegments("[draft] notes")
    eq(#segs, 1); eq(segs[1].class, "text")
    eq(Segments.labelSegments("[icon=]")[1].class, "text", "an empty name is not a token")
end)

test("upper() leaves an icon token's name as it is", function()
    package.loaded["ffi/utf8proc"] = { uppercase_dumb = function(t) return t:upper() end }
    package.loaded["lib/bookshelf_text_segments"] = nil
    local S2 = dofile("lib/bookshelf_text_segments.lua")
    eq(S2.upper("my [icon=cat.paw] shelf"), "MY [icon=cat.paw] SHELF")
end)

print(string.format("\ntext_segments: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
