--***********************************************************
--**  PNG Photo Map Viewer (B41)
--***********************************************************

require "ISUI/ISCollapsableWindow"

PhotoMapWindow = ISCollapsableWindow:derive("PhotoMapWindow")

-- itemFullType -> texture path
PhotoMapWindow.textures = {
    ["PhotoMap.shelter1"] = "media/textures/shelter1.png",
}

PhotoMapWindow.instances = {}

function PhotoMapWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setResizable(true)
    -- required: UIManager only dispatches key events to elements that want them
    self:setWantKeyEvents(true)
end

function PhotoMapWindow:clampOffset()
    local vw = self.width
    local vh = self.height - self:titleBarHeight()
    local dw = self.texW * self.zoom
    local dh = self.texH * self.zoom

    if dw <= vw then
        self.offX = (vw - dw) / 2
    else
        if self.offX > 0 then self.offX = 0 end
        if self.offX < vw - dw then self.offX = vw - dw end
    end

    if dh <= vh then
        self.offY = (vh - dh) / 2
    else
        if self.offY > 0 then self.offY = 0 end
        if self.offY < vh - dh then self.offY = vh - dh end
    end
end

function PhotoMapWindow:prerender()
    ISCollapsableWindow.prerender(self)

    local top = self:titleBarHeight()
    self:drawRect(0, top, self.width, self.height - top, 1.0, 0.05, 0.05, 0.05)

    if not self.texture then
        self:drawText(getText("IGUI_PhotoMap_NoTexture"), 10, top + 10, 1, 0.4, 0.4, 1, UIFont.Small)
        return
    end

    self:clampOffset()

    self:setStencilRect(0, top, self.width, self.height - top)
    self:drawTextureScaled(self.texture,
        self.offX, top + self.offY,
        self.texW * self.zoom, self.texH * self.zoom,
        1, 1, 1, 1)
    self:clearStencilRect()
end

function PhotoMapWindow:onMouseDown(x, y)
    if y < self:titleBarHeight() then
        return ISCollapsableWindow.onMouseDown(self, x, y)
    end
    self.dragging = true
    self:bringToTop()
    return true
end

function PhotoMapWindow:onMouseUp(x, y)
    self.dragging = false
    return ISCollapsableWindow.onMouseUp(self, x, y)
end

function PhotoMapWindow:onMouseUpOutside(x, y)
    self.dragging = false
    return ISCollapsableWindow.onMouseUpOutside(self, x, y)
end

function PhotoMapWindow:onMouseMove(dx, dy)
    if self.dragging then
        self.offX = self.offX + dx
        self.offY = self.offY + dy
        return true
    end
    return ISCollapsableWindow.onMouseMove(self, dx, dy)
end

function PhotoMapWindow:onMouseWheel(del)
    local top = self:titleBarHeight()
    local mx = self:getMouseX()
    local my = self:getMouseY() - top

    local old = self.zoom
    local new = old * (del < 0 and 1.15 or (1 / 1.15))
    if new < 0.1 then new = 0.1 end
    if new > 8.0 then new = 8.0 end
    if new == old then return true end

    -- keep the point under the cursor fixed
    self.offX = mx - (mx - self.offX) * (new / old)
    self.offY = my - (my - self.offY) * (new / old)
    self.zoom = new
    return true
end

function PhotoMapWindow:close()
    PhotoMapWindow.instances[self.texPath] = nil
    self:removeFromUIManager()
end

function PhotoMapWindow:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE
end

function PhotoMapWindow:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then
        self:close()
    end
end

function PhotoMapWindow:new(x, y, w, h, texPath)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.texPath = texPath
    o.texture = getTexture(texPath)
    o.texW = o.texture and o.texture:getWidth() or 0
    o.texH = o.texture and o.texture:getHeight() or 0
    o.zoom = 1.0
    o.offX = 0
    o.offY = 0
    o.dragging = false
    o.resizable = true
    o.drawFrame = true
    o.title = getText("IGUI_PhotoMap_Title")
    return o
end

function PhotoMapWindow.open(texPath)
    local existing = PhotoMapWindow.instances[texPath]
    if existing then
        existing:setVisible(true)
        existing:bringToTop()
        return existing
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w = math.min(900, sw - 100)
    local h = math.min(700, sh - 100)

    local ui = PhotoMapWindow:new((sw - w) / 2, (sh - h) / 2, w, h, texPath)
    ui:initialise()
    ui:addToUIManager()

    if not ui.texture then
        print("[PhotoMap] texture not found: " .. tostring(texPath))
    else
        -- fit to window on first open
        local top = ui:titleBarHeight()
        local sx = ui.width / ui.texW
        local sy = (ui.height - top) / ui.texH
        ui.zoom = math.min(sx, sy)
        print("[PhotoMap] opened: " .. tostring(texPath) ..
              " size=" .. tostring(ui.texW) .. "x" .. tostring(ui.texH))
    end

    PhotoMapWindow.instances[texPath] = ui
    return ui
end

local function onReadPhotoMap(player, texPath)
    PhotoMapWindow.open(texPath)
end

local function onFillContextMenu(player, context, items)
    local actual = ISInventoryPane.getActualItems(items)
    for i = 1, #actual do
        local item = actual[i]
        local texPath = PhotoMapWindow.textures[item:getFullType()]
        if texPath then
            context:addOption(getText("ContextMenu_PhotoMap_Read"),
                player, onReadPhotoMap, texPath)
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillContextMenu)
