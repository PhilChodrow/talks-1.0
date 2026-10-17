-- {{< staged NAME [from=2] [to=5] [captions=true] [height=560px] [dir=assets/figures] >}}
-- Reads <dir>/NAME.stages.json and emits one .r-stack: stage 1 is the base image, every later
-- stage is a .fragment image that covers the one below it (all stages share one bbox).

local function kw(kwargs, key)
  local v = kwargs[key]
  if v == nil then return nil end
  local s = pandoc.utils.stringify(v)
  if s == "" then return nil end
  return s
end

local function esc(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

return {
  staged = function(args, kwargs, meta)
    local name = pandoc.utils.stringify(args[1] or "")
    if name == "" then
      quarto.log.error("staged: figure name missing")
      return pandoc.Null()
    end
    local dir = kw(kwargs, "dir") or "assets/figures"
    local raw = read_file(dir .. "/" .. name .. ".stages.json")
    if not raw then
      -- Figures arrive from the staging layer later: show a visible stand-in, do not fail the render.
      quarto.log.warning("staged: no " .. dir .. "/" .. name .. ".stages.json yet (run scripts/sync_figures.py); emitting a placeholder")
      return pandoc.RawBlock("html", '<div class="staged-missing">[figure ' .. esc(name) .. ' not synced yet]</div>')
    end
    local m = quarto.json.decode(raw)
    local stages = m.stages
    local lo = tonumber(kw(kwargs, "from")) or 1
    local hi = tonumber(kw(kwargs, "to")) or #stages
    local want_captions = kw(kwargs, "captions") == "true"
    local w, h = m.bbox_pt[1], m.bbox_pt[2]

    local style = string.format("aspect-ratio: %s / %s; --staged-ar: %s;", tostring(w), tostring(h), tostring(w / h))
    local height = kw(kwargs, "height")
    if height then style = style .. " --staged-h: " .. height .. ";" end

    local out = { string.format('<div class="r-stack staged" data-figure="%s" style="%s">', esc(name), style) }
    local shown = {}
    for _, s in ipairs(stages) do
      if s.k >= lo and s.k <= hi then shown[#shown + 1] = s end
    end
    for i, s in ipairs(shown) do
      local src = dir .. "/" .. name .. "_step_" .. tostring(s.k) .. ".svg"
      local alt = esc(s.claim or "")
      if i == 1 then
        out[#out + 1] = string.format('  <img src="%s" alt="%s">', src, alt)
      else
        out[#out + 1] = string.format('  <img src="%s" alt="%s" class="fragment" data-fragment-index="%d">', src, alt, i - 1)
      end
    end
    out[#out + 1] = "</div>"
    local blocks = { pandoc.RawBlock("html", table.concat(out, "\n")) }

    if want_captions then
      local cap = read_file("_partials/captions/" .. name .. ".md")
      if not cap then
        quarto.log.warning("staged: captions=true but _partials/captions/" .. name .. ".md is missing")
      else
        local lines = {}
        for line in cap:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
        -- Captions share one grid cell and replace each other as the images do.
        local divs = {}
        for i, s in ipairs(shown) do
          local text = lines[s.k]
          if text then
            local cls = { "staged-caption" }
            local attrs = {}
            local n = #shown
            if i == 1 then
              if n > 1 then
                cls[#cls + 1] = "fragment"; cls[#cls + 1] = "fade-out"
                attrs["data-fragment-index"] = "1"
              end
            elseif i < n then
              cls[#cls + 1] = "fragment"; cls[#cls + 1] = "fade-in-then-out"
              attrs["data-fragment-index"] = tostring(i - 1)
            else
              cls[#cls + 1] = "fragment"
              attrs["data-fragment-index"] = tostring(i - 1)
            end
            divs[#divs + 1] = pandoc.Div(pandoc.read(text, "markdown").blocks, pandoc.Attr("", cls, attrs))
          end
        end
        blocks[#blocks + 1] = pandoc.Div(divs, pandoc.Attr("", { "r-stack", "staged-captions" }))
      end
    end
    return blocks
  end
}
