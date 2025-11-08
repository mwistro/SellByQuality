local ADDON = 'SellByQuality'

local defaults = {
  minQualityToSell = 2,
  sellLimitPerTick = 12,
  safeMode = true,
  enabled = true,
}

local function copyTbl(src)
  local t = {}
  for k,v in pairs(src) do t[k] = v end
  return t
end

local function ensureDB()
  if type(SellByQualityDB) ~= 'table' then
    SellByQualityDB = copyTbl(defaults)
  else
    for k,v in pairs(defaults) do
      if SellByQualityDB[k] == nil then
        SellByQualityDB[k] = v
      end
    end
  end
end

local function getVendorPrice(link)
  if not link then return 0 end
  return select(11, GetItemInfo(link)) or 0
end

local function coinString(copper)
  if GetCoinTextureString then
    return GetCoinTextureString(copper)
  end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  return string.format('%dg %ds %dc', g, s, c)
end

local function qualityName(q)
  local names = {
    [0] = 'poor', [1] = 'common', [2] = 'uncommon',
    [3] = 'rare', [4] = 'epic', [5] = 'legendary'
  }
  return names[q] or tostring(q)
end

local function c(msg)
  print('|cff00ff00[SBQ]|r ' .. (msg or ''))
end

local pendingSell = nil
local pendingTotal = 0
local pendingCount = 0

local f = CreateFrame('Frame')
f:RegisterEvent('ADDON_LOADED')
f:RegisterEvent('PLAYER_LOGIN')
f:RegisterEvent('MERCHANT_SHOW')
f:RegisterEvent('MERCHANT_CLOSED')

local function buildSellList()
  ensureDB()
  pendingSell = {}
  pendingTotal, pendingCount = 0, 0
  if not SellByQualityDB.enabled then return end

  local maxBags = (NUM_BAG_SLOTS or 4) + 1
  for bag = 0, maxBags do
    local slots = C_Container.GetContainerNumSlots(bag)
    if slots and slots > 0 then
      for slot = 1, slots do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
          local link = info.hyperlink
          local q = info.quality
          local count = info.stackCount or 1
          local hasNoValue = info.hasNoValue
          local isLocked = info.isLocked
          local priceEach = getVendorPrice(link)

          if link then
            local _, _, realQ = GetItemInfo(link)
            if realQ and (not q or realQ > q) then q = realQ end
          end

          local eligible = false
          if link and q and q <= 5 and q >= SellByQualityDB.minQualityToSell then
            eligible = true
          end

          if eligible and SellByQualityDB.safeMode then
            if isLocked or hasNoValue then
              eligible = false
            else
              local qi = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
              local isQuest = qi and (qi.isQuestItem or (qi.questID ~= nil))
              if isQuest then eligible = false end
            end
          end

          if eligible and (priceEach > 0) then
            table.insert(pendingSell, { bag = bag, slot = slot, link = link, count = count, priceEach = priceEach })
            pendingCount = pendingCount + 1
            pendingTotal = pendingTotal + (priceEach * count)
          end
        end
      end
    end
  end
end

local function doSellBatch()
  if not pendingSell or #pendingSell == 0 then return end
  local sold = 0
  local limit = SellByQualityDB.sellLimitPerTick or 12

  while sold < limit and #pendingSell > 0 do
    local item = table.remove(pendingSell, 1)
    local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
    if info and info.hyperlink == item.link then
      C_Container.UseContainerItem(item.bag, item.slot)
      sold = sold + 1
    end
  end

  if #pendingSell > 0 then
    C_Timer.After(0.2, doSellBatch)
  end
end

StaticPopupDialogs['SELLBYQUALITY_CONFIRM'] = {
  text = '%s',
  button1 = 'Sell',
  button2 = 'Cancel',
  OnAccept = function()
    doSellBatch()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function showConfirm()
  if not pendingSell or pendingCount == 0 then return end
  local qName = qualityName(SellByQualityDB.minQualityToSell)
  local msg = string.format('Sell |cffffff00%d|r items (≥ |cff00ff00%s|r) for |cff00ffff%s|r?',
    pendingCount, qName, coinString(pendingTotal))
  StaticPopup_Show('SELLBYQUALITY_CONFIRM', msg)
end

SLASH_SELLBYQUALITY1 = '/sbq'
SlashCmdList['SELLBYQUALITY'] = function(msg)
  ensureDB()
  local cmd, rest = msg:match('^(%S+)%s*(.*)$')
  cmd = cmd and cmd:lower() or ''

  if cmd == 'on' then
    SellByQualityDB.enabled = true
    c('|cff00ff00Addon enabled.|r')
  elseif cmd == 'off' then
    SellByQualityDB.enabled = false
    c('|cffff0000Addon disabled.|r')
  elseif cmd == 'quality' then
    local q = tonumber(rest)
    if q and q >= 0 and q <= 5 then
      SellByQualityDB.minQualityToSell = q
      c('Minimum quality set to |cffffff00' .. q .. '|r (' .. qualityName(q) .. ')')
    else
      c('Usage: |cff00ffff/sbq quality <0-5>|r  (|cff00ff002 = Uncommon|r)')
    end
  else
    c('Available commands:')
    print('|cff00ff00/sbq on|r - Enable addon')
    print('|cff00ff00/sbq off|r - Disable addon')
    print('|cff00ff00/sbq quality <0-5>|r - Set minimum quality (2 = Green)')
  end
end

f:SetScript('OnEvent', function(_, event, arg1)
  if event == 'ADDON_LOADED' and arg1 == ADDON then
    ensureDB()
    c('|cff00ff00Loaded.|r Type |cffffff00/sbq|r for commands.')
  elseif event == 'PLAYER_LOGIN' then
    ensureDB()
  elseif event == 'MERCHANT_SHOW' then
    ensureDB()
    buildSellList()
    if pendingCount > 0 then showConfirm() end
  elseif event == 'MERCHANT_CLOSED' then
    pendingSell, pendingCount, pendingTotal = nil, 0, 0
  end
end)
